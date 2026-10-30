"""A member's inbox arrangement for one chat: pinned (at most three) and archived."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import ThreadStateRead, ThreadStateRequest
from app.models import Conversation, ConversationMember, User

MAX_PINNED = 3


async def set_thread_state(
    db: AsyncSession, conversation: Conversation, user_id: UUID, change: ThreadStateRequest
) -> ThreadStateRead:
    """Apply a pin/archive change. The caller has already authorized the member.

    Pinning takes a lock on the user's own row, so two devices pinning different chats at once
    cannot both pass the three-pin check: the second waits, then counts the first's pin. (Locking
    the pinned rows would not do it — a pin made in parallel is a row the other count never saw.)
    """
    member = (
        await db.execute(
            select(ConversationMember)
            .where(ConversationMember.conversation_id == conversation.id, ConversationMember.user_id == user_id)
            .with_for_update()
        )
    ).scalar_one()
    now = datetime.now(UTC)
    if change.pinned is True and member.pinned_at is None:
        await db.execute(select(User.id).where(User.id == user_id).with_for_update())
        pinned = (
            await db.execute(
                select(func.count()).where(
                    ConversationMember.user_id == user_id, ConversationMember.pinned_at.is_not(None)
                )
            )
        ).scalar_one()
        if pinned >= MAX_PINNED:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='You can pin up to 3 chats')
        member.pinned_at = now
        member.archived_at = None  # a pinned chat belongs in the main list
    elif change.pinned is False:
        member.pinned_at = None
    if change.archived is True:
        member.archived_at = member.archived_at or now
        member.pinned_at = None  # archiving takes it out of the main list, pins included
    elif change.archived is False:
        member.archived_at = None
    await db.commit()
    return ThreadStateRead(pinned_at=member.pinned_at, archived=member.archived_at is not None)
