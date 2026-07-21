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
    left, right = ordered_pair(user_a, user_b)
    return (await db.execute(select(Match).where(Match.user_a_id == left, Match.user_b_id == right))).scalar_one_or_none()
