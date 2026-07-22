from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_verified_student
from app.features.activities.schema import ActivityCreate, ActivityRead
from app.features.activities.service import activity_count, activity_read, has_joined
from app.models import Activity, ActivityParticipant, User

router = APIRouter(prefix='/activities', tags=['activities'])


@router.post('', response_model=ActivityRead, status_code=status.HTTP_201_CREATED)
async def create_activity(payload: ActivityCreate, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    activity = Activity(
        creator_id=current_user.id,
        title=payload.title.strip(),
        description=payload.description,
        category=payload.category.strip().lower(),
        location=payload.location.strip(),
        start_time=payload.start_time,
        end_time=payload.end_time,
        max_participants=payload.max_participants,
    )
    db.add(activity)
    await db.flush()
    db.add(ActivityParticipant(activity_id=activity.id, user_id=current_user.id))
    await db.commit()
    await db.refresh(activity)
    return await activity_read(db, activity, current_user.id)


@router.get('', response_model=list[ActivityRead])
async def list_activities(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db), category: str | None = Query(default=None), limit: int = Query(default=30, ge=1, le=100)):
    count_subq = select(func.count(ActivityParticipant.id)).where(ActivityParticipant.activity_id == Activity.id).scalar_subquery()
    joined_subq = select(ActivityParticipant.id).where(ActivityParticipant.activity_id == Activity.id, ActivityParticipant.user_id == current_user.id).exists().correlate(Activity)

    stmt = select(Activity, count_subq.label('participant_count'), joined_subq.label('has_joined')).where(Activity.is_cancelled.is_(False), Activity.start_time >= datetime.now(UTC))
    if category:
        stmt = stmt.where(Activity.category == category.strip().lower())

    result = await db.execute(stmt.order_by(Activity.start_time.asc()).limit(limit))
    rows = result.all()

    return [
        await activity_read(db, activity, current_user.id, participant_count=p_count, has_joined_status=h_joined)
        for activity, p_count, h_joined in rows
    ]


@router.get('/{activity_id}', response_model=ActivityRead)
async def get_activity(activity_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    activity = await db.get(Activity, activity_id)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    return await activity_read(db, activity, current_user.id)


@router.post('/{activity_id}/join', response_model=ActivityRead)
async def join_activity(activity_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    activity = await db.get(Activity, activity_id)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    if not await has_joined(db, activity.id, current_user.id):
        count = await activity_count(db, activity.id)
        if activity.max_participants is not None and count >= activity.max_participants:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Activity is full')
        db.add(ActivityParticipant(activity_id=activity.id, user_id=current_user.id))
        await db.commit()
    return await activity_read(db, activity, current_user.id)


@router.delete('/{activity_id}/leave', response_model=ActivityRead)
async def leave_activity(activity_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    activity = await db.get(Activity, activity_id)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    participant = (await db.execute(select(ActivityParticipant).where(ActivityParticipant.activity_id == activity.id, ActivityParticipant.user_id == current_user.id))).scalar_one_or_none()
    if participant is not None:
        await db.delete(participant)
        await db.commit()
    return await activity_read(db, activity, current_user.id)
