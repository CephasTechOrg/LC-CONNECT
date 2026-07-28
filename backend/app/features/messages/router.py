from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_verified_user
from app.features.messages.schema import (
    MessageCreate,
    MessageRead,
    MessageThreadRead,
    MessagingCapabilities,
    RecipientSearchResult,
    StaffThreadCreate,
    UnreadSummary,
)
from app.features.messages.service import (
    delete_message,
    list_threads_for_user,
    message_read,
    page_thread,
    persist_message_idempotent,
    sync_thread,
    unread_summary,
)
from app.features.messages.staff_messaging import create_staff_thread, search_recipients
from app.models import User
from app.shared.conversations import (
    accessible_conversation,
    active_member_ids,
    addressing_ids_for_conversations,
)
from app.shared.policies import can_message_as_staff
from app.shared.rate_limit import recipient_search_limit, staff_thread_limit

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
    return [message_read(message) for message in messages]


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
    return [message_read(message) for message in messages]


@router.post('/threads/{match_id}', response_model=MessageRead, status_code=status.HTTP_201_CREATED)
async def send_message(match_id: UUID, payload: MessageCreate, current_user: User = Depends(require_verified_user), db: AsyncSession = Depends(get_db)):
    conversation = await accessible_conversation(db, match_id, current_user.id)
    message, _ = await persist_message_idempotent(
        db,
        sender_id=current_user.id,
        match_id=conversation.match_id,
        conversation_id=conversation.id,
        body=payload.body.strip(),
        client_message_id=payload.client_message_id,
    )
    return message_read(message)


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
    await broadcast_message_deleted(message.conversation_id, message.id, members)
    return message_read(message)
