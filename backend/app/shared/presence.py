"""Who may see whose presence, and the last-seen record — shared by the realtime tracker and the
messages presence endpoint (neither may import the other feature's modules).

The rule, as in WhatsApp: presence is visible between two people who share a one-to-one chat
(a DM or a staff DM — never a group), are not blocked either way, and have *both* left
"Show online status" on. Reciprocal on purpose: someone who hides theirs cannot watch others.
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import and_, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.models import Block, Conversation, ConversationMember, Profile, UserPresence

PRESENCE_KINDS = ('dm', 'staff_dm')


async def shows_presence(db: AsyncSession, user_id: UUID) -> bool:
    value = (
        await db.execute(select(Profile.show_presence).where(Profile.user_id == user_id))
    ).scalar_one_or_none()
    return True if value is None else bool(value)


async def presence_audience(db: AsyncSession, user_id: UUID) -> list[UUID]:
    """Everyone who may see `user_id`'s presence right now — one query.

    Empty when `user_id` hides theirs. Otherwise the other active member of each of their active
    one-to-one chats who also shows theirs and is not blocked either way.
    """
    if not await shows_presence(db, user_id):
        return []
    me = aliased(ConversationMember)
    other = aliased(ConversationMember)
    rows = (
        await db.execute(
            select(other.user_id)
            .select_from(me)
            .join(Conversation, Conversation.id == me.conversation_id)
            .join(other, and_(other.conversation_id == me.conversation_id, other.user_id != user_id))
            .join(Profile, Profile.user_id == other.user_id)
            .outerjoin(
                Block,
                or_(
                    and_(Block.blocker_id == user_id, Block.blocked_id == other.user_id),
                    and_(Block.blocker_id == other.user_id, Block.blocked_id == user_id),
                ),
            )
            .where(
                me.user_id == user_id,
                me.status == 'active',
                other.status == 'active',
                Conversation.kind.in_(PRESENCE_KINDS),
                Profile.show_presence.is_(True),
                Block.id.is_(None),
            )
            .distinct()
        )
    ).scalars().all()
    return list(rows)


async def record_last_seen(db: AsyncSession, user_id: UUID, at: datetime) -> None:
    """Upsert the user's last-seen time (caller need not commit)."""
    await db.execute(
        pg_insert(UserPresence)
        .values(user_id=user_id, last_seen_at=at)
        .on_conflict_do_update(index_elements=['user_id'], set_={'last_seen_at': at})
    )
    await db.commit()


async def last_seen_at(db: AsyncSession, user_id: UUID) -> datetime | None:
    return (
        await db.execute(select(UserPresence.last_seen_at).where(UserPresence.user_id == user_id))
    ).scalar_one_or_none()
