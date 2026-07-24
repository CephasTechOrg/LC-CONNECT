from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_verified_student
from app.features.messages.schema import MessageCreate, MessageRead, MessageThreadRead, UnreadSummary
from app.features.messages.service import (
    list_threads_for_user,
    message_read,
    page_thread,
    persist_message_idempotent,
    sync_thread,
    unread_summary,
)
from app.models import User
from app.shared.conversations import accessible_conversation, addressing_ids_for_conversations

router = APIRouter(prefix='/messages', tags=['messages'])


@router.get('/threads', response_model=list[MessageThreadRead])
async def list_threads(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    """The unified inbox — DM and group threads, newest activity first."""
    return await list_threads_for_user(db, current_user.id)


@router.get('/unread-summary', response_model=UnreadSummary)
async def get_unread_summary(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    """Total + per-conversation unread counts — seeds the tab + per-row badges. Keyed by the
    client-facing addressing id (match id for DMs, conversation id for groups)."""
    total, per_conversation = await unread_summary(db, current_user.id)
    addressing = await addressing_ids_for_conversations(db, list(per_conversation))
    external = {addressing[conversation_id]: count for conversation_id, count in per_conversation.items()}
    return UnreadSummary(total=sum(external.values()), per_conversation=external)


@router.get('/threads/{match_id}', response_model=list[MessageRead])
async def get_thread(
    match_id: UUID,
    current_user: User = Depends(require_verified_student),
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
    current_user: User = Depends(require_verified_student),
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
async def send_message(match_id: UUID, payload: MessageCreate, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
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
