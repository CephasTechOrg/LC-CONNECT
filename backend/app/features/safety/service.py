"""Safety domain logic: blocks and reports persistence."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.realtime.runtime import revoke_pair_access
from app.features.safety.schema import ReportCreate
from app.models import Block, Message, Report


async def add_block(db: AsyncSession, blocker_id: UUID, blocked_id: UUID) -> None:
    existing = (await db.execute(select(Block).where(Block.blocker_id == blocker_id, Block.blocked_id == blocked_id))).scalar_one_or_none()
    if existing is None:
        db.add(Block(blocker_id=blocker_id, blocked_id=blocked_id))
        await db.commit()
        # Immediately drop any live conversation the two users share (core rule 6/10).
        await revoke_pair_access(blocker_id, blocked_id)


async def remove_block(db: AsyncSession, blocker_id: UUID, blocked_id: UUID) -> None:
    existing = (await db.execute(select(Block).where(Block.blocker_id == blocker_id, Block.blocked_id == blocked_id))).scalar_one_or_none()
    if existing is not None:
        await db.delete(existing)
        await db.commit()


async def create_report(db: AsyncSession, reporter_id: UUID, payload: ReportCreate) -> Report:
    # Snapshot the reported message's text (and attribute its author) at report time, so the
    # evidence survives the message — or its whole group — being deleted afterwards.
    message_body = None
    reported_user_id = payload.reported_user_id
    if payload.message_id is not None:
        message = await db.get(Message, payload.message_id)
        if message is not None:
            message_body = message.body
            reported_user_id = reported_user_id or message.sender_id
    report = Report(
        reporter_id=reporter_id,
        reported_user_id=reported_user_id,
        activity_id=payload.activity_id,
        group_id=payload.group_id,
        message_id=payload.message_id,
        message_body=message_body,
        reason=payload.reason.strip(),
        details=payload.details,
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)
    return report
