"""Admin/moderation domain logic: suspension and activity takedown."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.realtime.runtime import disconnect_user
from app.models import Activity, User
from app.shared.audit import record_audit


async def suspend_user(db: AsyncSession, user_id: UUID, *, actor_id: UUID | None = None) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    before = {'status': user.status, 'is_active': user.is_active}
    user.status = 'suspended'
    user.is_active = False
    if actor_id is not None:
        await record_audit(
            db,
            actor_id=actor_id,
            action='user.suspend',
            target_type='user',
            target_id=user.id,
            before_data=before,
            after_data={'status': user.status, 'is_active': user.is_active},
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


async def remove_activity(db: AsyncSession, activity_id: UUID) -> Activity:
    activity = await db.get(Activity, activity_id)
    if activity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    activity.is_cancelled = True
    await db.commit()
    return activity
