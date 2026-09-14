"""Connections domain logic: deterministic match pairing."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Match


def ordered_pair(user_a: UUID, user_b: UUID) -> tuple[UUID, UUID]:
    ordered = sorted([user_a, user_b], key=lambda value: str(value))
    return ordered[0], ordered[1]


async def existing_match(db: AsyncSession, user_a: UUID, user_b: UUID) -> Match | None:
    """The match row for this pair, **including one that has been disconnected**.

    Reconnecting reuses the row (clearing `disconnected_at`) rather than inserting a second one,
    which the `uq_match_pair` constraint would reject anyway. Callers asking "are these two
    connected right now" want [active_match] instead.
    """
    left, right = ordered_pair(user_a, user_b)
    return (await db.execute(select(Match).where(Match.user_a_id == left, Match.user_b_id == right))).scalar_one_or_none()


async def active_match(db: AsyncSession, user_a: UUID, user_b: UUID) -> Match | None:
    """The match only while it is live — a disconnected pair is not connected."""
    match = await existing_match(db, user_a, user_b)
    return None if match is None or match.disconnected_at is not None else match
