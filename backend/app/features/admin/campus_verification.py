"""Admin campus verification — manual badge grant separate from email OTP (ADR-008 Phase 2)."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.shared.audit import record_audit


def _campus_snapshot(user: User) -> dict[str, str | bool | None]:
    return {
        'campus_verified': user.campus_verified,
        'campus_verified_at': user.campus_verified_at.isoformat() if user.campus_verified_at else None,
        'campus_verified_by_id': str(user.campus_verified_by_id) if user.campus_verified_by_id else None,
    }


async def campus_verify_user(db: AsyncSession, user_id: UUID, *, actor_id: UUID) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    if user.role == 'admin':
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail='Admin accounts do not use campus verification',
        )
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail='User must confirm their email before campus verification',
        )
    if user.campus_verified:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='User is already campus verified')

    before = _campus_snapshot(user)
    now = datetime.now(UTC)
    user.campus_verified = True
    user.campus_verified_at = now
    user.campus_verified_by_id = actor_id

    await record_audit(
        db,
        actor_id=actor_id,
        action='user.campus_verify',
        target_type='user',
        target_id=user.id,
        before_data=before,
        after_data=_campus_snapshot(user),
    )
    await db.commit()
    await db.refresh(user)
    return user


async def revoke_campus_verification(
    db: AsyncSession,
    user_id: UUID,
    *,
    actor_id: UUID,
    reason: str | None = None,
) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    if not user.campus_verified:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='User is not campus verified')

    before = _campus_snapshot(user)
    user.campus_verified = False
    user.campus_verified_at = None
    user.campus_verified_by_id = None

    after = _campus_snapshot(user)
    if reason:
        after['reason'] = reason.strip()

    await record_audit(
        db,
        actor_id=actor_id,
        action='user.campus_verify_revoke',
        target_type='user',
        target_id=user.id,
        before_data=before,
        after_data=after,
    )
    await db.commit()
    await db.refresh(user)
    return user
