"""Activities domain logic: participation (race-safe join/leave), counts, read-model assembly."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.activities.schema import ActivityParticipantRead, ActivityRead
from app.models import Activity, ActivityParticipant, Profile


async def activity_count(db: AsyncSession, activity_id: UUID) -> int:
    return int((await db.execute(select(func.count()).select_from(ActivityParticipant).where(ActivityParticipant.activity_id == activity_id))).scalar_one())


async def participants_read(db: AsyncSession, activity: Activity) -> list[ActivityParticipantRead]:
    """The roster (names + avatars), organizer first, in one query. Activities are public, so
    this is visible to any verified student — it's a list, not a management surface."""
    rows = (
        await db.execute(
            select(
                ActivityParticipant.user_id,
                Profile.id,
                Profile.display_name,
                Profile.avatar_url,
            )
            .outerjoin(Profile, Profile.user_id == ActivityParticipant.user_id)
            .where(ActivityParticipant.activity_id == activity.id)
            .order_by(ActivityParticipant.created_at.asc())
        )
    ).all()
    return [
        ActivityParticipantRead(
            user_id=user_id,
            profile_id=profile_id,
            display_name=display_name,
            avatar_url=avatar_url,
            is_creator=(user_id == activity.creator_id),
        )
        for user_id, profile_id, display_name, avatar_url in rows
    ]


async def has_joined(db: AsyncSession, activity_id: UUID, user_id: UUID) -> bool:
    participant = (await db.execute(select(ActivityParticipant).where(ActivityParticipant.activity_id == activity_id, ActivityParticipant.user_id == user_id))).scalar_one_or_none()
    return participant is not None


async def join_activity(db: AsyncSession, activity_id: UUID, user_id: UUID) -> Activity:
    """Join an activity, idempotently and **race-safely**. A `SELECT … FOR UPDATE` on the activity
    row serializes concurrent joins, so `max_participants` can never be exceeded and a double-tap
    can't duplicate (the membership check runs under the lock). The caller commits — holding the
    lock through the insert — mirroring the groups capacity pattern.
    """
    activity = (
        await db.execute(select(Activity).where(Activity.id == activity_id).with_for_update())
    ).scalar_one_or_none()
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    if not await has_joined(db, activity_id, user_id):
        if activity.max_participants is not None and await activity_count(db, activity_id) >= activity.max_participants:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Activity is full')
        db.add(ActivityParticipant(activity_id=activity_id, user_id=user_id))
    return activity


async def leave_activity(db: AsyncSession, activity_id: UUID, user_id: UUID) -> Activity:
    """Leave an activity (idempotent). The caller commits."""
    activity = await db.get(Activity, activity_id)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    participant = (
        await db.execute(
            select(ActivityParticipant).where(
                ActivityParticipant.activity_id == activity_id,
                ActivityParticipant.user_id == user_id,
            )
        )
    ).scalar_one_or_none()
    if participant is not None:
        await db.delete(participant)
    return activity


async def activity_read(db: AsyncSession, activity: Activity, user_id: UUID, participant_count: int | None = None, has_joined_status: bool | None = None) -> ActivityRead:
    if participant_count is None:
        participant_count = await activity_count(db, activity.id)
    if has_joined_status is None:
        has_joined_status = await has_joined(db, activity.id, user_id)

    return ActivityRead(
        id=activity.id,
        creator_id=activity.creator_id,
        title=activity.title,
        description=activity.description,
        category=activity.category,
        location=activity.location,
        banner_url=activity.banner_url,
        start_time=activity.start_time,
        end_time=activity.end_time,
        max_participants=activity.max_participants,
        participant_count=participant_count,
        has_joined=has_joined_status,
        is_cancelled=activity.is_cancelled,
        created_at=activity.created_at,
    )


async def creator_activity(db: AsyncSession, activity_id: UUID, user_id: UUID) -> Activity:
    """Load an activity for a creator-only action: 404 if missing/cancelled, 403 if not the creator."""
    activity = await db.get(Activity, activity_id)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    if activity.creator_id != user_id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Only the creator can do this')
    return activity


async def update_activity(db: AsyncSession, activity: Activity, changes: dict) -> None:
    """Apply a partial edit. Rejects an end_time that isn't after the (possibly new) start_time."""
    start = changes.get('start_time', activity.start_time)
    end = changes.get('end_time', activity.end_time)
    if end is not None and end <= start:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='end_time must be after start_time')
    for field in ('title', 'description', 'category', 'location', 'start_time', 'end_time', 'max_participants'):
        if field in changes:
            value = changes[field]
            if field in ('title', 'location') and isinstance(value, str):
                value = value.strip()
            elif field == 'category' and isinstance(value, str):
                value = value.strip().lower()
            setattr(activity, field, value)
