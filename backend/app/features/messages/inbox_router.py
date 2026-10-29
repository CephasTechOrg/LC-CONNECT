"""A member's own inbox controls — mute, pin, archive — plus message search and a DM partner's
presence. Kept out of `router.py` for the line cap; included by it."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_verified_user
from app.features.messages.inbox_state import set_thread_state
from app.features.messages.membership import set_muted
from app.features.messages.presence_read import partner_presence
from app.features.messages.schema import (
    MessageSearchHit,
    PresenceRead,
    ThreadMuteRequest,
    ThreadStateRead,
    ThreadStateRequest,
)
from app.features.messages.search import search_messages
from app.models import User
from app.shared.conversations import accessible_conversation

router = APIRouter()


@router.patch('/threads/{match_id}/mute', status_code=status.HTTP_204_NO_CONTENT)
async def mute_thread(
    match_id: UUID,
    payload: ThreadMuteRequest,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """Mute or unmute a conversation for yourself — no message or reaction pushes while muted.
    Works for DMs and groups alike; messages still arrive and count as unread."""
    conversation = await accessible_conversation(db, match_id, current_user.id)
    await set_muted(db, conversation, current_user.id, payload.muted)
    from app.features.realtime.broadcasts import broadcast_conversation_muted

    await broadcast_conversation_muted(
        current_user.id, conversation.match_id or conversation.id, payload.muted
    )


@router.get('/threads/{match_id}/presence', response_model=PresenceRead)
async def get_thread_presence(
    match_id: UUID,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
):
    """Your DM partner's "Online" / "Last seen", if you may see it — reciprocal, as in
    WhatsApp: if either of you hides it, neither sees it. Not available for groups."""
    conversation = await accessible_conversation(db, match_id, current_user.id)
    return await partner_presence(db, conversation, current_user.id)


@router.patch('/threads/{match_id}/state', response_model=ThreadStateRead)
async def update_thread_state(
    match_id: UUID,
    payload: ThreadStateRequest,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> ThreadStateRead:
    """Pin (at most three) or archive a chat for yourself. Your other devices follow along."""
    conversation = await accessible_conversation(db, match_id, current_user.id)
    state = await set_thread_state(db, conversation, current_user.id, payload)
    from app.features.realtime.broadcasts import broadcast_conversation_state

    await broadcast_conversation_state(
        current_user.id,
        conversation.match_id or conversation.id,
        pinned_at=state.pinned_at.isoformat() if state.pinned_at else None,
        archived=state.archived,
    )
    return state


@router.get('/search', response_model=list[MessageSearchHit])
async def search(
    q: str = Query(min_length=2, max_length=80),
    limit: int = Query(default=20, ge=1, le=50),
    before: datetime | None = Query(default=None),
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> list[MessageSearchHit]:
    """Messages containing `q` in chats you are in, newest first. Page with `before` set to the
    last hit's `created_at`."""
    return await search_messages(db, current_user.id, q.strip(), limit=limit, before=before)
