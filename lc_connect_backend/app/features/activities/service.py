"""Activities domain logic: participation counts and read-model assembly."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.activities.schema import ActivityRead
from app.models import Activity, ActivityParticipant


async def activity_count(db: AsyncSession, activity_id: UUID) -> int:
    return int((await db.execute(select(func.count()).select_from(ActivityParticipant).where(ActivityParticipant.activity_id == activity_id))).scalar_one())


async def has_joined(db: AsyncSession, activity_id: UUID, user_id: UUID) -> bool:
    participant = (await db.execute(select(ActivityParticipant).where(ActivityParticipant.activity_id == activity_id, ActivityParticipant.user_id == user_id))).scalar_one_or_none()
    return participant is not None


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
        start_time=activity.start_time,
        end_time=activity.end_time,
        max_participants=activity.max_participants,
        participant_count=participant_count,
        has_joined=has_joined_status,
        is_cancelled=activity.is_cancelled,
        created_at=activity.created_at,
    )
