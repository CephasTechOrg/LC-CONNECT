from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin
from app.models import Activity, Profile, Report, User
from app.schemas import AdminUserRead, ReportRead, SuspendUserRequest

router = APIRouter(prefix='/admin', tags=['admin'])


@router.get('/users', response_model=list[AdminUserRead])
async def list_users(_: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User, Profile).join(Profile, Profile.user_id == User.id).order_by(User.created_at.desc()).limit(200))
    return [
        AdminUserRead(
            id=user.id,
            email=user.email,
            role=user.role,
            status=user.status,
            is_active=user.is_active,
            is_verified=user.is_verified,
            display_name=profile.display_name,
        )
        for user, profile in result.all()
    ]


@router.get('/reports', response_model=list[ReportRead])
async def list_reports(_: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    return list((await db.execute(select(Report).order_by(Report.created_at.desc()).limit(200))).scalars().all())


@router.post('/users/{user_id}/suspend')
async def suspend_user(user_id: UUID, payload: SuspendUserRequest, _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    user = await db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    user.status = 'suspended'
    user.is_active = False
    await db.commit()
    return {'status': 'suspended', 'user_id': str(user.id), 'reason': payload.reason}


@router.post('/activities/{activity_id}/remove')
async def remove_activity(activity_id: UUID, _: User = Depends(require_admin), db: AsyncSession = Depends(get_db)):
    activity = await db.get(Activity, activity_id)
    if activity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    activity.is_cancelled = True
    await db.commit()
    return {'status': 'removed', 'activity_id': str(activity.id)}
