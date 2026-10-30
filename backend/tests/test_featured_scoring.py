"""Featured-activity scoring: soon, nearly full and popular rank up; joined and full rank down."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from app.features.activities.featured import Candidate, pick, reason_for
from app.models import Activity

NOW = datetime(2026, 10, 29, 12, tzinfo=UTC)


def _c(n: int, *, hours: float, count: int = 0, cap: int | None = None, joined: bool = False) -> Candidate:
    activity = Activity(
        id=UUID(int=n), title=f'a{n}', category='social', location='x',
        start_time=NOW + timedelta(hours=hours), max_participants=cap,
    )
    return Candidate(activity, count, joined)


def test_sooner_wins_when_all_else_is_equal():
    assert pick([_c(1, hours=120), _c(2, hours=6)], now=NOW).activity.title == 'a2'


def test_a_joined_activity_gives_way_to_one_to_discover():
    assert pick([_c(1, hours=6, joined=True), _c(2, hours=6)], now=NOW).activity.title == 'a2'


def test_a_full_activity_is_not_featured_over_an_open_one():
    assert pick([_c(1, hours=5, count=10, cap=10), _c(2, hours=6, count=9)], now=NOW).activity.title == 'a2'


def test_exact_ties_go_to_the_smaller_id():
    assert pick([_c(2, hours=6), _c(1, hours=6)], now=NOW).activity.title == 'a1'


def test_reasons():
    assert reason_for(_c(1, hours=200, count=8, cap=10), now=NOW) == 'filling_up'
    assert reason_for(_c(1, hours=20), now=NOW) == 'starting_soon'
    assert reason_for(_c(1, hours=200, count=12), now=NOW) == 'popular'
    assert reason_for(_c(1, hours=200), now=NOW) == 'featured'
