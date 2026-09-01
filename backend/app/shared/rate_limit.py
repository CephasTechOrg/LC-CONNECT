"""Token-bucket rate limiter (in-memory) + optional Redis-backed ``aallow``.

``allow(key)`` stays sync and process-local (tests, conn-id keys).
``aallow(key)`` uses Redis when connected so limits are shared across instances;
falls back to memory on outage or when Redis is unset.

Rate limiting for **login/signup lives in Supabase Auth** — this module is only for
*authenticated* (and a few public) abuse caps.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable, Hashable

from fastapi import Depends, HTTPException, Request, status

from app.config import settings
from app.dependencies import require_verified_user
from app.models import User
from app.shared.redis_client import get_redis

logger = logging.getLogger('lc_connect.rate_limit')

# Every RateLimiter registers here so a periodic task can drop idle buckets (bounded memory).
_REGISTRY: list[RateLimiter] = []

# Atomic token-bucket in Redis (parity with in-memory allow semantics).
_TOKEN_BUCKET_LUA = """
local key = KEYS[1]
local capacity = tonumber(ARGV[1])
local refill = tonumber(ARGV[2])
local now = tonumber(ARGV[3])
local cost = tonumber(ARGV[4])
local data = redis.call('HMGET', key, 'tokens', 'ts')
local tokens = tonumber(data[1])
local ts = tonumber(data[2])
if tokens == nil then
  tokens = capacity
  ts = now
end
tokens = math.min(capacity, tokens + (now - ts) * refill)
local allowed = 0
if tokens >= cost then
  tokens = tokens - cost
  allowed = 1
end
redis.call('HSET', key, 'tokens', tokens, 'ts', now)
local ttl = math.ceil(capacity / refill) * 2 + 60
redis.call('EXPIRE', key, ttl)
return allowed
"""


def prune_idle_buckets(idle_seconds: float) -> int:
    """Drop buckets untouched for `idle_seconds` across every limiter. Returns count removed.
    Call periodically so the in-memory bucket dicts never grow without bound."""
    return sum(limiter.prune(idle_seconds) for limiter in _REGISTRY)


class RateLimiter:
    def __init__(
        self,
        capacity: int,
        per_seconds: float,
        clock: Callable[[], float] = time.monotonic,
        *,
        name: str | None = None,
    ) -> None:
        if capacity <= 0 or per_seconds <= 0:
            raise ValueError('capacity and per_seconds must be positive')
        self._capacity = float(capacity)
        self._refill_per_sec = capacity / per_seconds
        self._clock = clock
        self._name = name or 'anon'
        # key -> [tokens, last_refill_ts]
        self._buckets: dict[Hashable, list[float]] = {}
        _REGISTRY.append(self)

    def allow(self, key: Hashable, cost: float = 1.0) -> bool:
        """Consume `cost` tokens for `key` in this process. Returns False when dry."""
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

    async def aallow(self, key: Hashable, cost: float = 1.0) -> bool:
        """Distributed check when Redis is up; otherwise same as ``allow``."""
        client = get_redis()
        if client is None:
            return self.allow(key, cost)
        redis_key = f'lcconnect:{settings.environment_slug}:rl:{self._name}:{key}'
        try:
            allowed = await client.eval(
                _TOKEN_BUCKET_LUA,
                1,
                redis_key,
                self._capacity,
                self._refill_per_sec,
                time.time(),
                cost,
            )
            return bool(allowed)
        except Exception:  # noqa: BLE001 — availability over perfect enforcement
            logger.warning('redis rate-limit failed (%s) — memory fallback', self._name, exc_info=True)
            return self.allow(key, cost)

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

_DAY = 86_400


class UserRateLimit:
    """A FastAPI dependency that caps one action to `limit` per `per_seconds` per user (429 over)."""

    def __init__(self, action: str, limit: int, per_seconds: float, message: str) -> None:
        self.action = action
        self._message = message
        self._limiter = RateLimiter(limit, per_seconds, name=action)

    async def __call__(self, current_user: User = Depends(require_verified_user)) -> User:
        if not await self._limiter.aallow(current_user.id):
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
scholar_upload_limit = UserRateLimit(
    'scholar_upload', settings.rate_limit_scholar_uploads_per_day, _DAY,
    "You've uploaded too many files today — try again tomorrow.",
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
recipient_search_limit = UserRateLimit(
    'recipient_search', settings.rate_limit_recipient_searches_per_minute, 60,
    'Too many searches — please slow down.',
)
invite_resend_limit = UserRateLimit(
    'invite_resend', settings.rate_limit_invite_resends_per_day, _DAY,
    "You've resent too many invites today — try again tomorrow.",
)
campus_post_create_limit = UserRateLimit(
    'campus_post_create', settings.rate_limit_campus_post_creates_per_day, _DAY,
    "You've drafted too many campus posts today — try again tomorrow.",
)
campus_post_publish_limit = UserRateLimit(
    'campus_post_publish', settings.rate_limit_campus_post_publishes_per_day, _DAY,
    "You've published too many campus posts today — try again tomorrow.",
)
attendance_check_in_limiter = RateLimiter(
    settings.rate_limit_attendance_check_ins_per_minute,
    60,
    name='attendance_check_in',
)
message_send_limit = UserRateLimit(
    'message_send', settings.rate_limit_message_sends_per_minute, 60,
    'Slow down — too many messages sent.',
)


# ── Public (unauthenticated) abuse limits ──────────────────────────────────────────


def client_ip(request: Request) -> str:
    """Best-effort caller identity for anonymous rate limiting.

    Behind Render/any reverse proxy the socket peer is the proxy, so the first hop of
    `X-Forwarded-For` is the real client. That header is spoofable by a *direct* caller, so this
    is an abuse speed-bump, not an authorization control — never gate access on it.
    """
    forwarded = request.headers.get('x-forwarded-for', '')
    if forwarded:
        first = forwarded.split(',')[0].strip()
        if first:
            return first
    return request.client.host if request.client else 'unknown'


class PublicRateLimit:
    """Caps an anonymous action per client IP (429 over)."""

    def __init__(self, action: str, limit: int, per_seconds: float, message: str) -> None:
        self.action = action
        self._message = message
        self._limiter = RateLimiter(limit, per_seconds, name=action)

    async def __call__(self, request: Request) -> None:
        if not await self._limiter.aallow(client_ip(request)):
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=self._message)


class KeyedRateLimit:
    """Caps an action per caller-supplied key (e.g. the email a reset was requested for)."""

    def __init__(self, action: str, limit: int, per_seconds: float, message: str) -> None:
        self.action = action
        self._message = message
        self._limiter = RateLimiter(limit, per_seconds, name=action)

    def check(self, key: str) -> None:
        """Sync memory-only check (tests). Prefer ``acheck`` in request handlers."""
        if not self._limiter.allow(key.strip().lower()):
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=self._message)

    async def acheck(self, key: str) -> None:
        if not await self._limiter.aallow(key.strip().lower()):
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=self._message)


_HOUR = 3_600

employer_register_limit = PublicRateLimit(
    'employer_register', settings.rate_limit_employer_registrations_per_hour, _HOUR,
    'Too many registration attempts. Please try again later.',
)
forgot_password_ip_limit = PublicRateLimit(
    'forgot_password_ip', settings.rate_limit_password_resets_per_hour, _HOUR,
    'Too many password reset requests. Please try again later.',
)
forgot_password_email_limit = KeyedRateLimit(
    'forgot_password_email', settings.rate_limit_password_resets_per_email_per_hour, _HOUR,
    'Too many password reset requests. Please try again later.',
)
