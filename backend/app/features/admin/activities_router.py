"""Admin activity curation (`/admin/activities/...`): list upcoming activities and choose the
campus pick that leads the Activities tab and Home for everyone.

Kept out of `admin/router.py` for the line cap — same pattern as `scholar_profiles_router`.
Takedowns stay with moderation (`POST /admin/activities/{id}/remove` in `router.py`).
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin_aal2
from app.features.admin.schema import ActivityFeatureRequest, AdminActivityRead
from app.models import Activity, ActivityParticipant, Profile, User
from app.shared.audit import record_audit

router = APIRouter()

# A pin is a campaign, not a permanent fixture: the automatic pick takes over again after this.
MAX_PIN = timedelta(days=60)


@router.get('/activities', response_model=list[AdminActivityRead])
async def list_upcoming_activities(
    limit: int = Query(default=100, ge=1, le=200),
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[AdminActivityRead]:
    now = datetime.now(UTC)
    count = (
        select(func.count(ActivityParticipant.id))
        .where(ActivityParticipant.activity_id == Activity.id)
        .correlate(Activity)
        .scalar_subquery()
    )
    rows = (
        await db.execute(
            select(Activity, count, Profile.display_name)
            .outerjoin(Profile, Profile.user_id == Activity.creator_id)
            .where(Activity.is_cancelled.is_(False), Activity.start_time > now)
            .order_by(Activity.start_time)
            .limit(limit)
        )
    ).all()
    return [
        AdminActivityRead(
            id=a.id,
            title=a.title,
            category=a.category,
            location=a.location,
            start_time=a.start_time,
            end_time=a.end_time,
            participant_count=n,
            max_participants=a.max_participants,
            creator_name=name,
            featured_until=a.featured_until if a.featured_until and a.featured_until > now else None,
        )
        for a, n, name in rows
    ]


@router.post('/activities/{activity_id}/feature', status_code=status.HTTP_204_NO_CONTENT)
async def feature_activity(
    activity_id: UUID,
    payload: ActivityFeatureRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> None:
    now = datetime.now(UTC)
    if not now < payload.until <= now + MAX_PIN:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail='Pick an end date within the next 60 days',
        )
    activity = await db.get(Activity, activity_id, with_for_update=True)
    if activity is None or activity.is_cancelled:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    # One campus pick at a time: pinning a new one replaces the old, so two admins cannot leave
    # students guessing which pin wins.
    await db.execute(
        update(Activity)
        .where(Activity.id != activity_id, Activity.featured_until > now)
        .values(featured_until=None, featured_by=None)
    )
    activity.featured_until = payload.until
    activity.featured_by = actor.id
    await record_audit(
        db,
        actor_id=actor.id,
        action='activity.feature',
        target_type='activity',
        target_id=activity.id,
        after_data={'featured_until': payload.until.isoformat()},
    )
    await db.commit()


@router.delete('/activities/{activity_id}/feature', status_code=status.HTTP_204_NO_CONTENT)
async def unfeature_activity(
    activity_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> None:
    activity = await db.get(Activity, activity_id)
    if activity is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Activity not found')
    activity.featured_until = None
    activity.featured_by = None
    await record_audit(
        db, actor_id=actor.id, action='activity.unfeature', target_type='activity', target_id=activity.id
    )
    await db.commit()
