"""Which activity is featured — the same one for everyone, on Home and on Activities.

An admin pin (`Activity.featured_until` in the future) wins. Otherwise the soonest upcoming
activities are scored on three bounded signals, weighted to sum to 1:

- **timing** (0.45): sooner ranks higher, by a smooth exponential decay over about three days;
- **scarcity** (0.20): close to full ranks up, unlimited is neutral, full is pushed down;
- **participation** (0.35): attendance relative to the most-attended candidate.

An activity the viewer already joined is nudged down (discovery over repeats), a full one hard
down, and exact ties break on id so the pick never flickers. The weights match
`mobile/lib/features/activities/data/featured_ranking.dart`, which stays as the app's offline
fallback; `tests/test_featured_parity.py` keeps the two equal.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Literal
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Activity, ActivityParticipant

W_TIMING = 0.45
W_SCARCITY = 0.20
W_PARTICIPATION = 0.35
JOINED_PENALTY = 0.15
FULL_PENALTY = 0.20
FILLING_UP_RATIO = 0.7
STARTING_SOON = timedelta(hours=48)
POPULAR_THRESHOLD = 10
# How many of the soonest activities compete. The timing signal makes anything later irrelevant.
CANDIDATES = 60

# An activity with no end time counts as running for this long after it starts.
DEFAULT_DURATION = timedelta(hours=2)


def still_on(now: datetime):
    """Upcoming or happening now: not yet ended (or, with no end time, started under 2h ago)."""
    return func.coalesce(Activity.end_time, Activity.start_time + DEFAULT_DURATION) > now


FeaturedReason = Literal['pinned', 'filling_up', 'starting_soon', 'popular', 'featured']


@dataclass(frozen=True)
class Candidate:
    activity: Activity
    participant_count: int
    has_joined: bool


@dataclass(frozen=True)
class FeaturedPick:
    activity: Activity
    participant_count: int
    has_joined: bool
    reason: FeaturedReason


def score(c: Candidate, *, pool_max: int, now: datetime) -> float:
    a = c.activity
    hours_until = (a.start_time - now).total_seconds() / 3600
    timing = math.exp(-hours_until / 72)
    cap = a.max_participants
    if cap is None or cap <= 0:
        scarcity = 0.3
    else:
        ratio = c.participant_count / cap
        scarcity = 0.1 if ratio >= 1 else min(max(ratio, 0.0), 1.0)
    participation = 0.0 if pool_max == 0 else c.participant_count / pool_max
    value = W_TIMING * timing + W_SCARCITY * scarcity + W_PARTICIPATION * participation
    if c.has_joined:
        value -= JOINED_PENALTY
    if cap is not None and cap > 0 and c.participant_count >= cap:
        value -= FULL_PENALTY
    return value


def reason_for(c: Candidate, *, now: datetime) -> FeaturedReason:
    cap = c.activity.max_participants
    if cap and cap > 0 and FILLING_UP_RATIO <= c.participant_count / cap < 1:
        return 'filling_up'
    if c.activity.start_time - now <= STARTING_SOON:
        return 'starting_soon'
    if c.participant_count >= POPULAR_THRESHOLD:
        return 'popular'
    return 'featured'


def pick(candidates: list[Candidate], *, now: datetime) -> Candidate | None:
    if not candidates:
        return None
    pool_max = max(c.participant_count for c in candidates)
    return max(candidates, key=lambda c: (score(c, pool_max=pool_max, now=now), _reverse_id(c.activity.id)))


def _reverse_id(activity_id: UUID) -> int:
    # `max` keeps the largest key; negating makes an exact tie go to the *smaller* id, as the app does.
    return -activity_id.int


async def featured_activity(db: AsyncSession, viewer_id: UUID, *, now: datetime) -> FeaturedPick | None:
    count = (
        select(func.count(ActivityParticipant.id))
        .where(ActivityParticipant.activity_id == Activity.id)
        .correlate(Activity)
        .scalar_subquery()
    )
    joined = (
        select(ActivityParticipant.id)
        .where(ActivityParticipant.activity_id == Activity.id, ActivityParticipant.user_id == viewer_id)
        .exists()
        .correlate(Activity)
    )
    columns = select(Activity, count.label('n'), joined.label('joined')).where(Activity.is_cancelled.is_(False))

    pinned = (
        await db.execute(
            columns.where(Activity.featured_until > now, still_on(now)).order_by(Activity.featured_until.desc()).limit(1)
        )
    ).first()
    if pinned is not None:
        return FeaturedPick(pinned[0], pinned[1], pinned[2], 'pinned')

    rows = (
        await db.execute(columns.where(Activity.start_time > now).order_by(Activity.start_time).limit(CANDIDATES))
    ).all()
    best = pick([Candidate(a, n, j) for a, n, j in rows], now=now)
    if best is None:
        return None
    return FeaturedPick(best.activity, best.participant_count, best.has_joined, reason_for(best, now=now))
