"""Device-token persistence for push notifications."""

from __future__ import annotations

from collections.abc import Sequence
from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import DeviceToken


async def register_device(db: AsyncSession, user_id: UUID, token: str, platform: str) -> None:
    """Idempotent upsert on the unique token: re-registration never duplicates, and a
    shared device's token moves to the newest user (rec #4)."""
    stmt = pg_insert(DeviceToken).values(user_id=user_id, token=token, platform=platform)
    stmt = stmt.on_conflict_do_update(
        index_elements=['token'],
        set_={'user_id': user_id, 'platform': platform, 'updated_at': func.now()},
    )
    await db.execute(stmt)
    await db.commit()


async def unregister_device(db: AsyncSession, token: str) -> None:
    await db.execute(delete(DeviceToken).where(DeviceToken.token == token))
    await db.commit()


async def tokens_for_user(db: AsyncSession, user_id: UUID) -> list[str]:
    rows = await db.execute(select(DeviceToken.token).where(DeviceToken.user_id == user_id))
    return [row[0] for row in rows.all()]


async def prune_tokens(db: AsyncSession, tokens: Sequence[str]) -> None:
    if not tokens:
        return
    await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(tokens)))
    await db.commit()
