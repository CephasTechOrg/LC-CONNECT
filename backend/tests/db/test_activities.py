"""Activity participation — idempotent join/leave, capacity, and a real concurrent-join race
(the FOR UPDATE row lock must never let `max_participants` be exceeded)."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.features.activities.service import (
    activity_count,
    creator_activity,
    join_activity,
    leave_activity,
    participants_read,
    update_activity,
)
from app.models import Activity, ActivityParticipant


async def _activity(db, creator, *, max_participants=None) -> Activity:
    activity = Activity(
        creator_id=creator.id, title='Study Jam', category='study', location='Library',
        start_time=datetime.now(UTC) + timedelta(days=1), max_participants=max_participants,
    )
    db.add(activity)
    await db.flush()
    db.add(ActivityParticipant(activity_id=activity.id, user_id=creator.id))  # creator auto-joins
    await db.commit()
    return activity


async def test_join_and_leave_are_idempotent(db, factory):
    creator = await factory.user()
    joiner = await factory.user()
    activity = await _activity(db, creator)

    await join_activity(db, activity.id, joiner.id)
    await db.commit()
    assert await activity_count(db, activity.id) == 2

    await join_activity(db, activity.id, joiner.id)  # again → no duplicate
    await db.commit()
    assert await activity_count(db, activity.id) == 2

    await leave_activity(db, activity.id, joiner.id)
    await db.commit()
    assert await activity_count(db, activity.id) == 1

    await leave_activity(db, activity.id, joiner.id)  # again → no-op
    await db.commit()
    assert await activity_count(db, activity.id) == 1


async def test_full_activity_rejects_join(db, factory):
    creator = await factory.user()
    activity = await _activity(db, creator, max_participants=1)  # creator fills the only slot
    joiner = await factory.user()
    with pytest.raises(HTTPException) as exc:
        await join_activity(db, activity.id, joiner.id)
    assert exc.value.status_code == 409


async def test_cannot_join_cancelled_activity(db, factory):
    creator = await factory.user()
    activity = await _activity(db, creator)
    activity.is_cancelled = True
    await db.commit()
    joiner = await factory.user()
    with pytest.raises(HTTPException) as exc:
        await join_activity(db, activity.id, joiner.id)
    assert exc.value.status_code == 404


async def test_creator_can_edit_but_others_cannot(db, factory):
    creator = await factory.user()
    stranger = await factory.user()
    activity = await _activity(db, creator)

    # Non-creator → 403.
    with pytest.raises(HTTPException) as exc:
        await creator_activity(db, activity.id, stranger.id)
    assert exc.value.status_code == 403

    # Creator can edit.
    loaded = await creator_activity(db, activity.id, creator.id)
    await update_activity(db, loaded, {'title': '  New Title  ', 'category': 'Sports'})
    await db.commit()
    refreshed = await db.get(Activity, activity.id)
    assert refreshed.title == 'New Title'  # trimmed
    assert refreshed.category == 'sports'  # normalized


async def test_edit_rejects_end_before_start(db, factory):
    creator = await factory.user()
    activity = await _activity(db, creator)
    loaded = await creator_activity(db, activity.id, creator.id)
    with pytest.raises(HTTPException) as exc:
        await update_activity(db, loaded, {'end_time': activity.start_time})  # == start, not after
    assert exc.value.status_code == 400


async def test_cancelled_activity_is_hidden(db, factory):
    creator = await factory.user()
    activity = await _activity(db, creator)
    activity.is_cancelled = True
    await db.commit()
    # creator_activity treats a cancelled activity as gone (404), and joins are blocked.
    with pytest.raises(HTTPException) as exc:
        await creator_activity(db, activity.id, creator.id)
    assert exc.value.status_code == 404


async def test_participants_roster_lists_creator_first(db, factory):
    creator = await factory.user(display_name='Organizer', campus_verified=True)
    joiner = await factory.user(display_name='Joiner', is_verified=False, campus_verified=False)
    activity = await _activity(db, creator)
    await join_activity(db, activity.id, joiner.id)
    await db.commit()

    roster = await participants_read(db, activity)
    assert [p.display_name for p in roster] == ['Organizer', 'Joiner']  # organizer joined first
    assert roster[0].is_creator is True
    assert roster[1].is_creator is False
    assert roster[0].profile_id is not None  # for tap-through to the profile
    # is_verified is carried per-participant (drives the checkmark badge on the roster).
    assert roster[0].is_verified is True
    assert roster[1].is_verified is False


async def test_join_capacity_is_race_safe(db, sessions, factory):
    """5 users rush a 2-slot activity at once on separate transactions — the row lock must admit
    exactly 2, never more (the count-then-insert bug would let all 5 in)."""
    creator = await factory.user()
    activity = await _activity(db, creator, max_participants=3)  # creator + exactly 2 slots
    joiners = [await factory.user() for _ in range(5)]
    await db.commit()
    activity_id = activity.id
    ids = [u.id for u in joiners]

    async def join_on_own_session(user_id):
        async with sessions() as s:
            try:
                await join_activity(s, activity_id, user_id)
                await s.commit()
                return 'ok'
            except HTTPException:
                await s.rollback()
                return 'full'

    results = await asyncio.gather(*[join_on_own_session(uid) for uid in ids])
    assert results.count('ok') == 2  # exactly the 2 open slots
    assert await activity_count(db, activity_id) == 3  # creator + 2, never more
