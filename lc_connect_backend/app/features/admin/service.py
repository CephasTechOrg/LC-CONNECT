"""Admin/moderation domain logic: suspension and activity takedown."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Activity, User


async def suspend_user(db: AsyncSession, user_id: UUID) -> User:
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    user.status = 'suspended'
    user.is_active = False
    await db.commit()
    return user


async def remove_activity(db: AsyncSession, activity_id: UUID) -> Activity:
    activity = await db.get(Activity, activity_id)
    if activity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    activity.is_cancelled = True
    await db.commit()
    return activity
