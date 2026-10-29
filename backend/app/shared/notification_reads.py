"""Marking notifications read as a side effect of something else the user did.

Opening a chat is reading it, so a "reacted to your message" notification about that chat has
been seen too — it used to stay unread (and on the badge) until tapped in the notification list.
Here rather than in the notifications feature because the realtime read path calls it, and a
feature must not import another feature's service.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import func, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Notification


async def mark_chat_reactions_read(db: AsyncSession, user_id: UUID, addressing_id: UUID) -> list[UUID]:
    """Mark `user_id`'s unread reaction notifications for this chat read and return their ids.
    Served by the partial unread index; a no-op (and no frame) when there are none."""
    ids = (
        await db.execute(
            update(Notification)
            .where(
                Notification.user_id == user_id,
                Notification.type == 'message_reaction',
                Notification.target_id == addressing_id,
                Notification.read_at.is_(None),
            )
            .values(read_at=func.now())
            .returning(Notification.id)
        )
    ).scalars().all()
    if ids:
        await db.commit()
    return list(ids)
