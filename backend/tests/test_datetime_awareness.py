"""Client-supplied instants must be timezone-aware.

Beta report #9 was a client rendering bug, but tracing it surfaced a real server-side defect in the
same family: nothing required an offset on an inbound datetime. A naive value has no defined
instant, and accepting one had two consequences —

1. it reached a ``timestamptz`` column and was silently reinterpreted in the session timezone, and
2. it was compared against an aware value loaded from the database, which raises
   ``TypeError: can't compare offset-naive and offset-aware datetimes`` — an unhandled 500.

``AwareDatetime`` turns both into a 422 at the edge. Every client already sends an offset
(Flutter serialises with ``toUtc().toIso8601String()``), so nothing well-formed is rejected.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta, timezone

import pytest
from pydantic import ValidationError

from app.features.activities.schema import ActivityCreate, ActivityUpdate
from app.features.campus_hub.schema import CampusPostCreate, CampusPostUpdate

_NAIVE = datetime(2026, 9, 16, 18, 0)
_AWARE = datetime(2026, 9, 16, 22, 0, tzinfo=UTC)


def _activity(**overrides):
    payload = {
        'title': 'Evening study group',
        'category': 'academic',
        'location': 'Carnegie Library',
        'start_time': _AWARE,
    }
    payload.update(overrides)
    return payload


class TestActivityCreate:
    def test_accepts_an_aware_start_time(self):
        activity = ActivityCreate(**_activity())
        assert activity.start_time.tzinfo is not None

    def test_rejects_a_naive_start_time(self):
        with pytest.raises(ValidationError) as exc:
            ActivityCreate(**_activity(start_time=_NAIVE))
        assert 'start_time' in str(exc.value)

    def test_rejects_a_naive_end_time(self):
        with pytest.raises(ValidationError):
            ActivityCreate(**_activity(end_time=_NAIVE))

    def test_still_rejects_an_end_before_the_start(self):
        # The pre-existing ordering rule must survive the type change.
        with pytest.raises(ValidationError):
            ActivityCreate(**_activity(end_time=_AWARE - timedelta(hours=1)))

    def test_accepts_a_non_utc_offset(self):
        # Aware means aware — it does not have to be UTC. This is the shape a client sending a
        # local offset rather than `Z` would produce.
        eastern = datetime(2026, 9, 16, 18, 0, tzinfo=timezone(timedelta(hours=-4)))
        activity = ActivityCreate(**_activity(start_time=eastern))
        assert activity.start_time.utcoffset() == timedelta(hours=-4)
        # ...and it denotes the same instant as the UTC form used elsewhere in this file.
        assert activity.start_time == _AWARE


class TestActivityUpdate:
    """The model where the naive/aware mix actually produced a 500.

    A PATCH carrying only ``end_time`` reached ``update_activity``, which compares it against the
    **stored** ``start_time``. Stored values are aware, so a naive payload raised.
    """

    def test_rejects_a_naive_end_time_alone(self):
        with pytest.raises(ValidationError) as exc:
            ActivityUpdate(end_time=_NAIVE)
        assert 'end_time' in str(exc.value)

    def test_rejects_a_naive_start_time_alone(self):
        with pytest.raises(ValidationError):
            ActivityUpdate(start_time=_NAIVE)

    def test_accepts_an_aware_partial_update(self):
        update = ActivityUpdate(end_time=_AWARE)
        assert update.end_time == _AWARE
        assert update.start_time is None

    def test_an_empty_update_is_still_valid(self):
        assert ActivityUpdate().end_time is None


class TestCampusPostScheduling:
    """Same defect shape: partial updates compare a payload value against a stored one."""

    def _post(self, **overrides):
        payload = {'kind': 'announcement', 'title': 'Library hours', 'body': 'Open late all week.'}
        payload.update(overrides)
        return payload

    def test_create_rejects_a_naive_publish_at(self):
        with pytest.raises(ValidationError):
            CampusPostCreate(**self._post(publish_at=_NAIVE))

    def test_create_rejects_a_naive_expires_at(self):
        with pytest.raises(ValidationError):
            CampusPostCreate(**self._post(expires_at=_NAIVE))

    def test_create_accepts_aware_scheduling(self):
        post = CampusPostCreate(
            **self._post(publish_at=_AWARE, expires_at=_AWARE + timedelta(days=7))
        )
        assert post.publish_at is not None
        assert post.publish_at.tzinfo is not None

    def test_update_rejects_a_naive_expires_at_alone(self):
        with pytest.raises(ValidationError):
            CampusPostUpdate(expires_at=_NAIVE)

    def test_update_accepts_an_aware_expires_at_alone(self):
        assert CampusPostUpdate(expires_at=_AWARE).expires_at == _AWARE
