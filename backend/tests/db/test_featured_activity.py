"""The featured activity, campus picks, and the activities that stay listed while running."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.activities.featured import featured_activity, still_on
from app.features.activities.service import update_activity
from app.features.admin.activities_router import feature_activity, unfeature_activity
from app.features.admin.schema import ActivityFeatureRequest
from app.models import Activity, ActivityParticipant


async def _activity(db, creator, *, title, starts_in, ends_in=None, cap=None) -> Activity:
    now = datetime.now(UTC)
    activity = Activity(
        creator_id=creator.id, title=title, category='social', location='Quad',
        start_time=now + starts_in, end_time=None if ends_in is None else now + ends_in,
        max_participants=cap,
    )
    db.add(activity)
    await db.flush()
    db.add(ActivityParticipant(activity_id=activity.id, user_id=creator.id))
    await db.commit()
    return activity


async def test_without_a_pin_the_score_decides(db, factory):
    creator, viewer = await factory.user(), await factory.user()
    await _activity(db, creator, title='Next month', starts_in=timedelta(days=30))
    await _activity(db, creator, title='Tomorrow', starts_in=timedelta(hours=20))

    chosen = await featured_activity(db, viewer.id, now=datetime.now(UTC))
    assert chosen.activity.title == 'Tomorrow'
    assert chosen.reason == 'starting_soon'


async def test_a_campus_pick_wins_and_replaces_the_previous_pick(db, factory):
    creator, viewer, admin = await factory.user(), await factory.user(), await factory.user()
    soon = await _activity(db, creator, title='Tomorrow', starts_in=timedelta(hours=20))
    later = await _activity(db, creator, title='Career fair', starts_in=timedelta(days=12))
    until = datetime.now(UTC) + timedelta(days=7)

    await feature_activity(soon.id, ActivityFeatureRequest(until=until), actor=admin, db=db)
    await feature_activity(later.id, ActivityFeatureRequest(until=until), actor=admin, db=db)

    chosen = await featured_activity(db, viewer.id, now=datetime.now(UTC))
    assert (chosen.activity.title, chosen.reason) == ('Career fair', 'pinned')
    pinned = (await db.execute(select(Activity.title).where(Activity.featured_until.is_not(None)))).scalars().all()
    assert pinned == ['Career fair']

    await unfeature_activity(later.id, actor=admin, db=db)
    assert (await featured_activity(db, viewer.id, now=datetime.now(UTC))).activity.title == 'Tomorrow'


async def test_a_pin_must_end_within_sixty_days(db, factory):
    creator, admin = await factory.user(), await factory.user()
    activity = await _activity(db, creator, title='x', starts_in=timedelta(days=1))
    with pytest.raises(HTTPException) as exc:
        await feature_activity(
            activity.id, ActivityFeatureRequest(until=datetime.now(UTC) + timedelta(days=90)), actor=admin, db=db
        )
    assert exc.value.status_code == 422


async def test_an_activity_stays_listed_while_it_is_running(db, factory):
    creator = await factory.user()
    running = await _activity(db, creator, title='Running', starts_in=-timedelta(hours=1), ends_in=timedelta(hours=1))
    no_end = await _activity(db, creator, title='No end', starts_in=-timedelta(hours=1))
    over = await _activity(db, creator, title='Over', starts_in=-timedelta(hours=3), ends_in=-timedelta(hours=1))

    ids = set((await db.execute(select(Activity.id).where(still_on(datetime.now(UTC))))).scalars())
    assert running.id in ids and no_end.id in ids
    assert over.id not in ids


async def test_the_cap_cannot_drop_below_who_already_joined(db, factory):
    creator = await factory.user()
    activity = await _activity(db, creator, title='x', starts_in=timedelta(days=1))
    db.add(ActivityParticipant(activity_id=activity.id, user_id=(await factory.user()).id))
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await update_activity(db, activity, {'max_participants': 1})
    assert exc.value.status_code == 409
