"""Suspended-account appeal workflow (#22)."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import SuspensionAppeal, User
from app.shared.audit import record_audit


async def get_open_appeal(db: AsyncSession, user_id: UUID) -> SuspensionAppeal | None:
    result = await db.execute(
        select(SuspensionAppeal)
        .where(SuspensionAppeal.user_id == user_id, SuspensionAppeal.status == 'open')
        .order_by(SuspensionAppeal.created_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


async def submit_appeal(db: AsyncSession, user: User, *, message: str) -> SuspensionAppeal:
    if user.status != 'suspended':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Account is not suspended')
    existing = await get_open_appeal(db, user.id)
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='You already have an open appeal — our team will review it soon.',
        )
    appeal = SuspensionAppeal(user_id=user.id, message=message.strip(), status='open')
    db.add(appeal)
    await db.commit()
    await db.refresh(appeal)
    return appeal


async def list_appeals(db: AsyncSession, *, status_filter: str | None = 'open') -> list[SuspensionAppeal]:
    stmt = select(SuspensionAppeal).order_by(SuspensionAppeal.created_at.asc())
    if status_filter:
        stmt = stmt.where(SuspensionAppeal.status == status_filter)
    result = await db.execute(stmt)
    return list(result.scalars().all())


async def review_appeal(
    db: AsyncSession,
    appeal_id: UUID,
    *,
    actor_id: UUID,
    new_status: str,
    note: str | None,
) -> SuspensionAppeal:
    if new_status not in {'dismissed', 'resolved'}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid appeal status')
    appeal = await db.get(SuspensionAppeal, appeal_id)
    if appeal is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Appeal not found')
    if appeal.status != 'open':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Appeal is already closed')
    before = {'status': appeal.status}
    appeal.status = new_status
    appeal.admin_note = note.strip() if note else None
    appeal.reviewed_by_id = actor_id
    appeal.reviewed_at = datetime.now(UTC)
    await record_audit(
        db,
        actor_id=actor_id,
        action=f'suspension_appeal.{new_status}',
        target_type='suspension_appeal',
        target_id=appeal.id,
        before_data=before,
        after_data={'status': appeal.status, 'user_id': str(appeal.user_id), 'note': appeal.admin_note},
    )
    await db.commit()
    await db.refresh(appeal)
    return appeal


def support_contact_email() -> str:
    return settings.support_email
