from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_verified_user
from app.features.messages.editing import edit_message
from app.features.messages.reactions import reactions_for, toggle_reaction
from app.features.messages.schema import (
    MessageCreate,
    MessageEditRequest,
    MessageRead,
    MessageReadBy,
    MessageThreadRead,
    MessagingCapabilities,
    ReactionSummary,
    RecipientSearchResult,
    StaffThreadCreate,
    UnreadSummary,
)
from app.features.messages.service import (
    delete_message,
    delivery_cursor,
    list_threads_for_user,
    message_read,
    page_thread,
    persist_message_idempotent,
    read_by,
    sync_thread,
    unread_summary,
)
from app.features.messages.staff_messaging import create_staff_thread, search_recipients
from app.models import User
from app.shared.conversations import (
    accessible_conversation,
    active_member_ids,
    active_members_with_mute,
    addressing_ids_for_conversations,
)
from app.shared.policies import can_message_as_staff
from app.shared.rate_limit import (
    message_edit_limit,
    message_send_limit,
    reaction_limit,
    recipient_search_limit,
    staff_thread_limit,
)

router = APIRouter(prefix='/messages', tags=['messages'])


@router.get('/capabilities', response_model=MessagingCapabilities)
async def get_messaging_capabilities(
    current_user: User = Depends(require_verified_user), db: AsyncSession = Depends(get_db)
) -> MessagingCapabilities:
    """Whether this account can start a new conversation with anyone (verified staff)."""
    return MessagingCapabilities(
        can_message_anyone=await can_message_as_staff(db, current_user),
        staff_messaging_enabled=settings.staff_messaging_enabled,
    )


@router.get('/search-recipients', response_model=list[RecipientSearchResult])
async def search_message_recipients(
    q: str = Query(default='', max_length=120),
    limit: int = Query(default=20, ge=1, le=50),
    current_user: User = Depends(recipient_search_limit),
    db: AsyncSession = Depends(get_db),
) -> list[RecipientSearchResult]:
    """Search students + staff to start a new conversation with — verified staff only."""
    if not await can_message_as_staff(db, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Staff messaging requires a verified campus position',
        )
    if not q.strip():
        return []
    return await search_recipients(db, actor=current_user, query=q, limit=limit)


@router.post('/staff-threads', response_model=MessageThreadRead, status_code=status.HTTP_201_CREATED)
async def start_staff_thread(
    payload: StaffThreadCreate,
    current_user: User = Depends(staff_thread_limit),
    db: AsyncSession = Depends(get_db),
) -> MessageThreadRead:
    """Get-or-create a conversation with `target_user_id` — no connection required, as long
    as one side is a verified staff messenger (see `can_message_as_staff`)."""
    return await create_staff_thread(db, actor=current_user, target_user_id=payload.target_user_id)


@router.get('/threads', response_model=list[MessageThreadRead])
async def list_threads(current_user: User = Depends(require_verified_user), db: AsyncSession = Depends(get_db)):
    """The unified inbox — DM, staff, and group threads, newest activity first."""
    return await list_threads_for_user(db, current_user.id)


@router.get('/unread-summary', response_model=UnreadSummary)
async def get_unread_summary(current_user: User = Depends(require_verified_user), db: AsyncSession = Depends(get_db)):
    """Total + per-conversation unread counts — seeds the tab + per-row badges. Keyed by the
    client-facing addressing id (match id for DMs, conversation id for groups)."""
    total, per_conversation = await unread_summary(db, current_user.id)
    addressing = await addressing_ids_for_conversations(db, list(per_conversation))
    external = {addressing[conversation_id]: count for conversation_id, count in per_conversation.items()}
    return UnreadSummary(total=sum(external.values()), per_conversation=external)


def _serialize_page(
    messages: list,
    cursor: tuple | None,
    reactions: dict[UUID, list[ReactionSummary]],
    *,
    sender_id: UUID,
) -> list[MessageRead]:
    """Serialize a page, marking the requester's own messages delivered up to `cursor`.

    Only the requester's own messages carry the flag: "delivered" is a fact about *my* message
    reaching someone else, and it is the sender who is shown the tick. Reporting it on a message
    somebody else sent would be telling you about your own receipt, which you already know.
    """
    return [
        message_read(
            message,
            delivered=(
                cursor is not None
                and message.sender_id == sender_id
                and (message.created_at, message.id) <= cursor
            ),
            reactions=reactions.get(message.id),
        )
        for message in messages
    ]


@router.get('/threads/{match_id}', response_model=list[MessageRead])
async def get_thread(
    match_id: UUID,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
    before_created_at: datetime | None = Query(default=None),
    before_id: UUID | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
):
    """Newest-first page of a conversation. Pass the oldest row's (created_at, id) as
    `before_*` to fetch the next older page (keyset pagination)."""
    conversation = await accessible_conversation(db, match_id, current_user.id)
    messages = await page_thread(
        db, conversation.id, before_created_at=before_created_at, before_id=before_id, limit=limit
    )
    # Two queries for the whole page, never per message — see `delivery_cursor` and
    # `reactions_for`.
    cursor = await delivery_cursor(db, conversation.id, exclude=current_user.id)
    reactions = await reactions_for(
        db, [m.id for m in messages], viewer_id=current_user.id
    )
    return _serialize_page(messages, cursor, reactions, sender_id=current_user.id)


@router.get('/threads/{match_id}/sync', response_model=list[MessageRead])
async def sync_thread_endpoint(
    match_id: UUID,
    after_created_at: datetime = Query(...),
    after_id: UUID = Query(...),
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
    limit: int = Query(default=100, ge=1, le=200),
):
    """Oldest-first messages after a cursor — reconnect catch-up."""
    conversation = await accessible_conversation(db, match_id, current_user.id)
    messages = await sync_thread(
        db, conversation.id, after_created_at=after_created_at, after_id=after_id, limit=limit
    )
    cursor = await delivery_cursor(db, conversation.id, exclude=current_user.id)
    reactions = await reactions_for(
        db, [m.id for m in messages], viewer_id=current_user.id
    )
    return _serialize_page(messages, cursor, reactions, sender_id=current_user.id)


@router.post('/threads/{match_id}', response_model=MessageRead, status_code=status.HTTP_201_CREATED)
async def send_message(
    match_id: UUID,
    payload: MessageCreate,
    current_user: User = Depends(message_send_limit),
    db: AsyncSession = Depends(get_db),
):
    conversation = await accessible_conversation(db, match_id, current_user.id)
    message, created = await persist_message_idempotent(
        db,
        sender_id=current_user.id,
        match_id=conversation.match_id,
        conversation_id=conversation.id,
        body=payload.body.strip(),
        client_message_id=payload.client_message_id,
    )
    if created:
        from app.features.realtime.runtime import emit_message_created

        recipients = await active_members_with_mute(db, conversation.id, exclude=current_user.id)
        await emit_message_created(
            message,
            sender_id=current_user.id,
            recipients=recipients,
        )
    return message_read(message)


@router.patch('/{message_id}', response_model=MessageRead)
async def edit_message_endpoint(
    message_id: UUID,
    payload: MessageEditRequest,
    current_user: User = Depends(message_edit_limit),
    db: AsyncSession = Depends(get_db),
):
    """Edit your own message, within the edit window (report #5).

    Sender only — deliberately asymmetric with delete, where a group admin may remove someone
    else's message. An admin able to *edit* one would hold a forgery primitive.
    """
    message = await edit_message(db, message_id, current_user.id, payload.body)
    from app.features.realtime.runtime import broadcast_message_edited

    members = await active_member_ids(db, message.conversation_id)
    await broadcast_message_edited(message, members)
    return message_read(message)


@router.put('/{message_id}/reactions/{emoji}', status_code=status.HTTP_204_NO_CONTENT)
async def add_reaction(
    message_id: UUID,
    emoji: str,
    current_user: User = Depends(reaction_limit),
    db: AsyncSession = Depends(get_db),
):
    """React to a message. Idempotent — reacting twice is success, not a conflict.

    `PUT` rather than `POST` precisely because it is idempotent: a double-tap, or a retry after a
    dropped response, must not need the client to reason about whether the first one landed.
    """
    conversation_id = await toggle_reaction(
        db, message_id=message_id, user_id=current_user.id, emoji=emoji, add=True
    )
    from app.features.realtime.runtime import broadcast_reaction

    await broadcast_reaction(
        conversation_id=conversation_id,
        message_id=message_id,
        user_id=current_user.id,
        emoji=emoji,
        added=True,
    )


@router.delete('/{message_id}/reactions/{emoji}', status_code=status.HTTP_204_NO_CONTENT)
async def remove_reaction(
    message_id: UUID,
    emoji: str,
    current_user: User = Depends(reaction_limit),
    db: AsyncSession = Depends(get_db),
):
    """Remove your reaction. Idempotent — removing one that is not there is success."""
    conversation_id = await toggle_reaction(
        db, message_id=message_id, user_id=current_user.id, emoji=emoji, add=False
    )
    from app.features.realtime.runtime import broadcast_reaction

    await broadcast_reaction(
        conversation_id=conversation_id,
        message_id=message_id,
        user_id=current_user.id,
        emoji=emoji,
        added=False,
    )


@router.get('/{message_id}/read-by', response_model=list[MessageReadBy])
async def get_message_read_by(
    message_id: UUID,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """Who has read this message.

    A group's answer to "was it seen" (report #21). A group bubble cannot carry a delivered or
    read tick without a rule for which members count and every member's boundary held on the
    client; this list is both cheaper and says more. Excludes the caller.
    """
    return await read_by(db, message_id, current_user.id)


@router.delete('/{message_id}', response_model=MessageRead)
async def delete_message_endpoint(
    message_id: UUID, current_user: User = Depends(require_verified_user), db: AsyncSession = Depends(get_db)
):
    """Delete a message for everyone (soft delete → tombstone). Sender anywhere; group admins in
    their group. Fans out a `message.deleted` event so open chats update live."""
    message = await delete_message(db, message_id, current_user.id)
    # Lazy import avoids a module-load cycle with the realtime package.
    from app.features.realtime.runtime import broadcast_message_deleted

    members = await active_member_ids(db, message.conversation_id)
    await broadcast_message_deleted(message, members)
    return message_read(message)
