"""Safety domain logic: blocks and reports persistence."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.safety.schema import ReportCreate
from app.models import Block, Report


async def add_block(db: AsyncSession, blocker_id: UUID, blocked_id: UUID) -> None:
    existing = (await db.execute(select(Block).where(Block.blocker_id == blocker_id, Block.blocked_id == blocked_id))).scalar_one_or_none()
    if existing is None:
        db.add(Block(blocker_id=blocker_id, blocked_id=blocked_id))
        await db.commit()


async def remove_block(db: AsyncSession, blocker_id: UUID, blocked_id: UUID) -> None:
    existing = (await db.execute(select(Block).where(Block.blocker_id == blocker_id, Block.blocked_id == blocked_id))).scalar_one_or_none()
    if existing is not None:
        await db.delete(existing)
        await db.commit()


async def create_report(db: AsyncSession, reporter_id: UUID, payload: ReportCreate) -> Report:
    report = Report(
        reporter_id=reporter_id,
        reported_user_id=payload.reported_user_id,
        activity_id=payload.activity_id,
        reason=payload.reason.strip(),
        details=payload.details,
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)
    return report
