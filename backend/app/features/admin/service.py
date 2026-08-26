"""Admin/moderation domain logic: suspension, report access/resolution, activity takedown."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.realtime.runtime import disconnect_user
from app.models import Activity, Report, User
from app.shared.audit import record_audit


async def suspend_user(
    db: AsyncSession,
    user_id: UUID,
    *,
    actor_id: UUID | None = None,
    reason: str | None = None,
) -> User:
    # Self-suspension is the hardest lockout in the system: `_ensure_active` rejects the account
    # on the very next request, so the admin can no longer authenticate — and reactivating
    # requires authenticating. Only another admin could undo it, and a sole admin could not be
    # rescued at all without direct database access.
    if actor_id is not None and actor_id == user_id:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='You cannot suspend your own account — ask another admin to do it.',
        )
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    before = {'status': user.status, 'is_active': user.is_active}
    user.status = 'suspended'
    user.is_active = False
    if actor_id is not None:
        after: dict = {'status': user.status, 'is_active': user.is_active}
        if reason is not None:
            after['reason'] = reason
        await record_audit(
            db,
            actor_id=actor_id,
            action='user.suspend',
            target_type='user',
            target_id=user.id,
            before_data=before,
            after_data=after,
        )
    await db.commit()
    # Immediately close the suspended user's live sockets (core rule 6/10).
    await disconnect_user(user_id)
    return user


async def reactivate_user(db: AsyncSession, user_id: UUID, *, actor_id: UUID | None = None) -> User:
    """Undo a suspension — without this, suspending the wrong account (or a mis-click) had no
    recovery path anywhere in the admin portal."""
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    if user.status != 'suspended':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='This user is not suspended')
    before = {'status': user.status, 'is_active': user.is_active}
    user.status = 'active'
    user.is_active = True
    if actor_id is not None:
        await record_audit(
            db,
            actor_id=actor_id,
            action='user.reactivate',
            target_type='user',
            target_id=user.id,
            before_data=before,
            after_data={'status': user.status, 'is_active': user.is_active},
        )
    await db.commit()
    return user


async def get_report_for_moderation(
    db: AsyncSession, report_id: UUID, *, actor_id: UUID
) -> Report:
    """Load one report and record that a moderator viewed it (PII / evidence access)."""
    report = await db.get(Report, report_id)
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Report not found')
    await record_audit(
        db,
        actor_id=actor_id,
        action='report.view',
        target_type='report',
        target_id=report.id,
        after_data={
            'status': report.status,
            'reported_user_id': str(report.reported_user_id) if report.reported_user_id else None,
            'reason': report.reason,
        },
    )
    await db.commit()
    return report


async def resolve_report(
    db: AsyncSession,
    report_id: UUID,
    *,
    actor_id: UUID,
    note: str | None = None,
) -> Report:
    """Mark a report resolved and audit the decision."""
    report = await db.get(Report, report_id)
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Report not found')
    if report.status == 'resolved':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Report is already resolved')
    before = {'status': report.status}
    report.status = 'resolved'
    after: dict = {'status': report.status}
    if note:
        after['note'] = note
    await record_audit(
        db,
        actor_id=actor_id,
        action='report.resolve',
        target_type='report',
        target_id=report.id,
        before_data=before,
        after_data=after,
    )
    await db.commit()
    await db.refresh(report)
    return report


async def remove_activity(db: AsyncSession, activity_id: UUID) -> Activity:
    activity = await db.get(Activity, activity_id)
    if activity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    activity.is_cancelled = True
    await db.commit()
    return activity
