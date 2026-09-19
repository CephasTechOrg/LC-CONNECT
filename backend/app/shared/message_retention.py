"""Purge soft-deleted messages past the configured retention window.

Ops: `python scripts/purge_soft_deleted_messages.py` (dry-run by default).
Policy: `docs/security/audit_and_data_retention.md`
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Message, MessageEdit


@dataclass
class MessagePurgeReport:
    retention_days: int
    cutoff: datetime
    eligible: int
    purged: int
    #: Edit-history rows removed. Counted separately because they are purged on their own clock:
    #: a message that was edited and never deleted still accumulates history that should not
    #: outlive the retention window.
    edits_purged: int = 0
    sample_ids: list[UUID] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return True


def retention_cutoff(*, retention_days: int, now: datetime | None = None) -> datetime:
    anchor = now or datetime.now(UTC)
    return anchor - timedelta(days=retention_days)


async def count_eligible_messages(db: AsyncSession, *, cutoff: datetime) -> int:
    return int(
        await db.scalar(
            select(func.count())
            .select_from(Message)
            .where(Message.deleted_at.is_not(None), Message.deleted_at < cutoff)
        )
        or 0
    )


async def sample_eligible_message_ids(
    db: AsyncSession, *, cutoff: datetime, limit: int = 10
) -> list[UUID]:
    result = await db.execute(
        select(Message.id)
        .where(Message.deleted_at.is_not(None), Message.deleted_at < cutoff)
        .order_by(Message.deleted_at.asc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def purge_soft_deleted_messages(
    db: AsyncSession,
    *,
    retention_days: int,
    apply: bool,
    now: datetime | None = None,
    batch_size: int = 500,
    sample_limit: int = 10,
) -> MessagePurgeReport:
    """Hard-delete message rows soft-deleted before the retention cutoff, and old edit history.

    Report snapshots (`reports.message_body`) are unaffected — evidence survives row purge.

    Edit history (`message_edits`) is purged on the **same window**, and needs its own pass. The
    foreign key cascades history away when a message row is purged, but that only covers messages
    that were *deleted*. A message that was edited and never deleted would otherwise keep its
    history forever — turning an audit trail with a purpose (explaining a message while someone
    might still report it) into a permanent record of everything anyone ever rephrased.
    """
    if retention_days < 1:
        raise ValueError('retention_days must be >= 1')
    if batch_size < 1:
        raise ValueError('batch_size must be >= 1')

    cutoff = retention_cutoff(retention_days=retention_days, now=now)
    eligible = await count_eligible_messages(db, cutoff=cutoff)
    sample_ids = await sample_eligible_message_ids(db, cutoff=cutoff, limit=sample_limit)

    if not apply:
        return MessagePurgeReport(
            retention_days=retention_days,
            cutoff=cutoff,
            eligible=eligible,
            purged=0,
            sample_ids=sample_ids,
        )

    purged = 0
    while True:
        ids_result = await db.execute(
            select(Message.id)
            .where(Message.deleted_at.is_not(None), Message.deleted_at < cutoff)
            .order_by(Message.deleted_at.asc())
            .limit(batch_size)
        )
        ids = list(ids_result.scalars().all())
        if not ids:
            break
        await db.execute(delete(Message).where(Message.id.in_(ids)))
        await db.commit()
        purged += len(ids)

    # Independent of the loop above: history on a message that was never deleted has no purge
    # trigger of its own, and `eligible == 0` does not mean there is none to remove.
    edits = await db.execute(
        delete(MessageEdit).where(MessageEdit.edited_at < cutoff).returning(MessageEdit.id)
    )
    edits_purged = len(list(edits.scalars().all()))
    await db.commit()

    return MessagePurgeReport(
        retention_days=retention_days,
        cutoff=cutoff,
        eligible=eligible,
        purged=purged,
        edits_purged=edits_purged,
        sample_ids=sample_ids,
    )
