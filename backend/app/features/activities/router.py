from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_email_confirmed_user
from app.features.activities import service
from app.features.activities.schema import (
    ActivityCreate,
    ActivityParticipantRead,
    ActivityRead,
    ActivityUpdate,
)
from app.features.activities.service import activity_read
from app.models import Activity, ActivityParticipant, User
from app.shared.image_processing import sanitize_avatar
from app.shared.rate_limit import avatar_upload_limit
from app.shared.storage import storage_service

router = APIRouter(prefix='/activities', tags=['activities'])


@router.post('', response_model=ActivityRead, status_code=status.HTTP_201_CREATED)
async def create_activity(payload: ActivityCreate, current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)):
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
async def list_activities(current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db), category: str | None = Query(default=None), limit: int = Query(default=30, ge=1, le=100)):
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
async def get_activity(activity_id: UUID, current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)):
    activity = await db.get(Activity, activity_id)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    return await activity_read(db, activity, current_user.id)


@router.get('/{activity_id}/participants', response_model=list[ActivityParticipantRead])
async def list_participants(activity_id: UUID, current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)):
    """The activity's roster (public — any verified student can view)."""
    activity = await db.get(Activity, activity_id)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    return await service.participants_read(db, activity)


@router.patch('/{activity_id}', response_model=ActivityRead)
async def edit_activity(activity_id: UUID, payload: ActivityUpdate, current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)):
    activity = await service.creator_activity(db, activity_id, current_user.id)
    await service.update_activity(db, activity, payload.model_dump(exclude_unset=True))
    await db.commit()
    return await activity_read(db, activity, current_user.id)


@router.post('/{activity_id}/cancel', response_model=ActivityRead)
async def cancel_activity(activity_id: UUID, current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)):
    """Creator cancels their activity (soft — the row stays, hidden from listings/joins)."""
    activity = await service.creator_activity(db, activity_id, current_user.id)
    activity.is_cancelled = True
    await db.commit()
    # `activity_read` 404s a cancelled activity elsewhere, but the creator gets the final state back.
    return await activity_read(db, activity, current_user.id)


@router.post('/{activity_id}/banner', response_model=ActivityRead, dependencies=[Depends(avatar_upload_limit)])
async def upload_activity_banner(
    activity_id: UUID,
    file: UploadFile = File(...),
    current_user: User = Depends(require_email_confirmed_user),
    db: AsyncSession = Depends(get_db),
):
    activity = await service.creator_activity(db, activity_id, current_user.id)
    data = await file.read()
    if len(data) > settings.max_profile_image_mb * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail='Image is too large')
    clean, content_type = sanitize_avatar(data)  # validates bytes + strips EXIF; preserves aspect
    activity.banner_url = storage_service.upload_activity_banner(activity.id, content_type, clean)
    await db.commit()
    return await activity_read(db, activity, current_user.id)


@router.post('/{activity_id}/join', response_model=ActivityRead)
async def join_activity(activity_id: UUID, current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)):
    activity = await service.join_activity(db, activity_id, current_user.id)  # race-safe under a row lock
    await db.commit()
    return await activity_read(db, activity, current_user.id)


@router.delete('/{activity_id}/leave', response_model=ActivityRead)
async def leave_activity(activity_id: UUID, current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)):
    activity = await service.leave_activity(db, activity_id, current_user.id)
    await db.commit()
    return await activity_read(db, activity, current_user.id)
