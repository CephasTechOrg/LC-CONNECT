"""Cross-feature authorization policies.

`users_are_blocked` is a relationship policy used by the connections, messages, and
safety features. Future policies (can_view_profile, can_connect, can_message) belong
here too — see architecture_review/00_current_state_review.md.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Block


async def users_are_blocked(db: AsyncSession, user_a: UUID, user_b: UUID) -> bool:
    result = await db.execute(
        select(Block).where(
            or_(
                (Block.blocker_id == user_a) & (Block.blocked_id == user_b),
                (Block.blocker_id == user_b) & (Block.blocked_id == user_a),
            )
        )
    )
    return result.scalar_one_or_none() is not None
