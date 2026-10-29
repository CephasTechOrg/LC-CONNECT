from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_verified_user
from app.features.messages import inbox_router
from app.features.messages.editing import edit_message
from app.features.messages.reaction_flow import apply_reaction
from app.features.messages.reactions import reactions_for, reactors_for
from app.features.messages.replies import (
    ReplyTargetError,
    preview_of,
    reply_previews_for,
    sender_name,
    validate_reply_target,
)
from app.features.messages.schema import (
    LinkPreviewRequest,
    MessageCreate,
    MessageEditRequest,
    MessageLinkPreviewRead,
    MessageReactor,
    MessageRead,
    MessageReadBy,
    MessageThreadRead,
    MessagingCapabilities,
    ReactionState,
    ReactionSummary,
    RecipientSearchResult,
    ReplyPreview,
    StaffThreadCreate,
    UnreadSummary,
)
from app.features.messages.service import (
    delete_message,
    delivery_cursor,
    message_read,
    page_thread,
    persist_message_idempotent,
    read_by,
    sync_thread,
    unread_summary,
)
from app.features.messages.staff_messaging import create_staff_thread, search_recipients
from app.features.messages.threads import list_threads_for_user
from app.models import User
from app.shared.conversations import (
    accessible_conversation,
    active_member_ids,
    active_members_with_mute,
    addressing_ids_for_conversations,
    assert_can_post,
)
from app.shared.policies import can_message_as_staff
from app.shared.rate_limit import (
    link_preview_limit,
    message_delete_limit,
    message_edit_limit,
    message_send_limit,
    reaction_limit,
    recipient_search_limit,
    staff_thread_limit,
)

router = APIRouter(prefix='/messages', tags=['messages'])
# Pin/archive, search and bulk presence (protocol 6) live in their own module for the line cap.
router.include_router(inbox_router.router)


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


@router.post('/link-preview', response_model=MessageLinkPreviewRead)
async def preview_chat_link(
    payload: LinkPreviewRequest,
    current_user: User = Depends(link_preview_limit),
) -> MessageLinkPreviewRead:
    """Unfurl the first http(s) URL in `payload.url` for a chat bubble or the composer.

    Uses the same SSRF-guarded fetch as campus-post previews. Soft-fails to `status='failed'`
    (still carrying the domain) so a dead page still gets a tappable hostname card. Never
    persists — each client caches; a send is not delayed for this.
    """
    from app.shared.link_preview import fetch_link_preview, first_http_url

    extracted = first_http_url(payload.url.strip())
    if extracted is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Enter a valid http(s) URL',
        )
    preview = await fetch_link_preview(extracted)
    return MessageLinkPreviewRead(
        url=extracted,
        domain=preview.domain,
        site_name=preview.site_name,
        title=preview.title,
        description=preview.description,
        image_url=preview.image_url,
        fetched_at=datetime.now(UTC),
        status=preview.status,
    )


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
    replies: dict[UUID, ReplyPreview] | None = None,
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
            reply=(replies or {}).get(message.id),
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
    replies = await reply_previews_for(db, messages)
    return _serialize_page(messages, cursor, reactions, sender_id=current_user.id, replies=replies)


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
    replies = await reply_previews_for(db, messages)
    return _serialize_page(messages, cursor, reactions, sender_id=current_user.id, replies=replies)


@router.post('/threads/{match_id}', response_model=MessageRead, status_code=status.HTTP_201_CREATED)
async def send_message(
    match_id: UUID,
    payload: MessageCreate,
    current_user: User = Depends(message_send_limit),
    db: AsyncSession = Depends(get_db),
):
    conversation = await accessible_conversation(db, match_id, current_user.id)
    await assert_can_post(db, conversation)
    reply = None
    if payload.reply_to_id is not None:
        try:
            target = await validate_reply_target(db, conversation.id, payload.reply_to_id)
        except ReplyTargetError as exc:
            code = (
                status.HTTP_409_CONFLICT
                if exc.code == 'reply_target_deleted'
                else status.HTTP_422_UNPROCESSABLE_CONTENT
            )
            raise HTTPException(status_code=code, detail=exc.code) from exc
        reply = preview_of(target, await sender_name(db, target.sender_id))
    message, created = await persist_message_idempotent(
        db,
        sender_id=current_user.id,
        match_id=conversation.match_id,
        conversation_id=conversation.id,
        body=payload.body.strip(),
        client_message_id=payload.client_message_id,
        reply_to_id=payload.reply_to_id,
    )
    if not created:
        # A retried send returns the original row — with the reply it was first sent with.
        reply = (await reply_previews_for(db, [message])).get(message.id)
    if created:
        from app.features.realtime.runtime import emit_message_created

        recipients = await active_members_with_mute(db, conversation.id, exclude=current_user.id)
        await emit_message_created(
            message,
            sender_id=current_user.id,
            recipients=recipients,
            reply=reply.model_dump(mode='json') if reply else None,
        )
    return message_read(message, reply=reply)


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


@router.put('/{message_id}/reactions/{emoji}', response_model=ReactionState)
async def add_reaction(
    message_id: UUID,
    emoji: str,
    current_user: User = Depends(reaction_limit),
    db: AsyncSession = Depends(get_db),
):
    """Make `emoji` your reaction to a message, replacing any other — one per person.

    `PUT` because it is idempotent: a double-tap, or a retry after a dropped response, needs no
    reasoning about whether the first landed. Returns the message's resulting reactions.
    """
    return await apply_reaction(
        db, message_id=message_id, actor_id=current_user.id, emoji=emoji, add=True
    )


@router.delete('/{message_id}/reactions/{emoji}', response_model=ReactionState)
async def remove_reaction(
    message_id: UUID,
    emoji: str,
    current_user: User = Depends(reaction_limit),
    db: AsyncSession = Depends(get_db),
):
    """Remove your reaction. Idempotent — removing one that is not there is success."""
    return await apply_reaction(
        db, message_id=message_id, actor_id=current_user.id, emoji=emoji, add=False
    )


@router.get('/{message_id}/reactions', response_model=list[MessageReactor])
async def get_message_reactors(
    message_id: UUID,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """Who reacted to this message and with what, newest first — including you."""
    return await reactors_for(db, message_id, current_user.id)


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
    message_id: UUID, current_user: User = Depends(message_delete_limit), db: AsyncSession = Depends(get_db)
):
    """Delete a message for everyone (soft delete → tombstone). Sender anywhere; group admins in
    their group. Fans out a `message.deleted` event so open chats update live."""
    message = await delete_message(db, message_id, current_user.id)
    # Lazy import avoids a module-load cycle with the realtime package.
    from app.features.realtime.runtime import broadcast_message_deleted

    members = await active_member_ids(db, message.conversation_id)
    await broadcast_message_deleted(message, members)
    return message_read(message)
