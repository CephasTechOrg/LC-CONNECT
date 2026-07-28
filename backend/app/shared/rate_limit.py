"""In-memory token-bucket rate limiter + a per-user HTTP abuse-limit dependency.

`RateLimiter` is O(1) per check, one bucket per key. The clock is injectable so tests are
deterministic. `discard`/`prune` keep the key space bounded; the Redis-backed distributed
version is a later slice behind the same `allow(key)` API. Used by the WebSocket gateway and
(via `UserRateLimit`) by the REST endpoints.

Rate limiting for **login/signup lives in Supabase Auth** (dashboard settings) — this module is
only for *authenticated* abuse (a signed-in user spamming expensive actions).
"""

from __future__ import annotations

import time
from collections.abc import Callable, Hashable

from fastapi import Depends, HTTPException, status

from app.config import settings
from app.dependencies import require_verified_user
from app.models import User

# Every RateLimiter registers here so a periodic task can drop idle buckets (bounded memory).
_REGISTRY: list[RateLimiter] = []


def prune_idle_buckets(idle_seconds: float) -> int:
    """Drop buckets untouched for `idle_seconds` across every limiter. Returns count removed.
    Call periodically so the in-memory bucket dicts never grow without bound."""
    return sum(limiter.prune(idle_seconds) for limiter in _REGISTRY)


class RateLimiter:
    def __init__(self, capacity: int, per_seconds: float, clock: Callable[[], float] = time.monotonic) -> None:
        if capacity <= 0 or per_seconds <= 0:
            raise ValueError('capacity and per_seconds must be positive')
        self._capacity = float(capacity)
        self._refill_per_sec = capacity / per_seconds
        self._clock = clock
        # key -> [tokens, last_refill_ts]
        self._buckets: dict[Hashable, list[float]] = {}
        _REGISTRY.append(self)  # so a background task can prune every limiter's idle buckets

    def allow(self, key: Hashable, cost: float = 1.0) -> bool:
        """Consume `cost` tokens for `key`. Returns False when the bucket is dry."""
        now = self._clock()
        bucket = self._buckets.get(key)
        if bucket is None:
            tokens = self._capacity
        else:
            tokens = min(self._capacity, bucket[0] + (now - bucket[1]) * self._refill_per_sec)
        if tokens >= cost:
            self._buckets[key] = [tokens - cost, now]
            return True
        self._buckets[key] = [tokens, now]
        return False

    def discard(self, key: Hashable) -> None:
        """Drop a key's bucket (e.g. on disconnect/unsubscribe)."""
        self._buckets.pop(key, None)

    def prune(self, idle_seconds: float) -> int:
        """Remove buckets untouched for `idle_seconds`. Returns count removed."""
        cutoff = self._clock() - idle_seconds
        stale = [key for key, (_, last) in self._buckets.items() if last < cutoff]
        for key in stale:
            del self._buckets[key]
        return len(stale)

    def __len__(self) -> int:
        return len(self._buckets)


# ── Per-user HTTP abuse limits ─────────────────────────────────────────────────────
#
# One token bucket per action, keyed by user id. A user may burst up to `limit`, then refills
# to a sustained ~`limit` per `per_seconds`. Applied to a handful of expensive/abusable actions
# so a signed-in user can't spam them; normal use never comes close. Values are generous on
# purpose (block abuse, never legitimate students). In-memory + single-instance for now — move
# the buckets to Redis when the API runs multiple workers.

_DAY = 86_400


class UserRateLimit:
    """A FastAPI dependency that caps one action to `limit` per `per_seconds` per user (429 over)."""

    def __init__(self, action: str, limit: int, per_seconds: float, message: str) -> None:
        self.action = action
        self._message = message
        self._limiter = RateLimiter(limit, per_seconds)

    async def __call__(self, current_user: User = Depends(require_verified_user)) -> User:
        # `require_verified_user` (not the student-matching gate) so staff-facing actions —
        # messaging search, campus publishing — can share the same limiter pattern.
        if not self._limiter.allow(current_user.id):
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=self._message)
        return current_user


# Limits come from settings (env-tunable, defaults in app/config.py) — one place to change them.
connection_request_limit = UserRateLimit(
    'connection_request', settings.rate_limit_connection_requests_per_day, _DAY,
    "You've sent too many connection requests today — try again tomorrow.",
)
group_create_limit = UserRateLimit(
    'group_create', settings.rate_limit_group_creates_per_day, _DAY,
    "You've created too many groups today — try again tomorrow.",
)
avatar_upload_limit = UserRateLimit(
    'avatar_upload', settings.rate_limit_avatar_uploads_per_day, _DAY,
    'Too many photo updates today — try again later.',
)
report_limit = UserRateLimit(
    'report', settings.rate_limit_reports_per_day, _DAY,
    "You've filed many reports today — thank you; please try again tomorrow.",
)
group_invite_limit = UserRateLimit(
    'group_invite', settings.rate_limit_group_invites_per_day, _DAY,
    "You've sent too many invites today — try again tomorrow.",
)
staff_thread_limit = UserRateLimit(
    'staff_thread', settings.rate_limit_staff_threads_per_day, _DAY,
    "You've started too many new conversations today — try again tomorrow.",
)
# Guards the recipient directory against scripted enumeration (staff-only, but still a
# name-listing surface).
recipient_search_limit = UserRateLimit(
    'recipient_search', settings.rate_limit_recipient_searches_per_minute, 60,
    'Too many searches — please slow down.',
)
campus_post_create_limit = UserRateLimit(
    'campus_post_create', settings.rate_limit_campus_post_creates_per_day, _DAY,
    "You've drafted too many campus posts today — try again tomorrow.",
)
campus_post_publish_limit = UserRateLimit(
    'campus_post_publish', settings.rate_limit_campus_post_publishes_per_day, _DAY,
    "You've published too many campus posts today — try again tomorrow.",
)
