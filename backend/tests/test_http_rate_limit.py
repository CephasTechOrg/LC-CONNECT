"""Per-user HTTP abuse limiting (token bucket + the FastAPI dependency)."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from app.shared.rate_limit import RateLimiter, UserRateLimit, prune_idle_buckets


def test_token_bucket_allows_up_to_capacity_then_blocks():
    now = [0.0]
    rl = RateLimiter(3, 100, clock=lambda: now[0])  # 3 per 100s, frozen clock
    assert rl.allow('u') and rl.allow('u') and rl.allow('u')
    assert not rl.allow('u')  # 4th within the window is blocked
    # A different user has an independent bucket.
    assert rl.allow('other')


def test_token_bucket_refills_over_time():
    now = [0.0]
    rl = RateLimiter(2, 100, clock=lambda: now[0])  # refills 1 token / 50s
    assert rl.allow('u') and rl.allow('u')
    assert not rl.allow('u')
    now[0] = 60  # ~1.2 tokens refilled
    assert rl.allow('u')  # allowed again after enough time
    assert not rl.allow('u')


def test_prune_drops_idle_buckets_and_keeps_fresh_ones():
    now = [1000.0]
    rl = RateLimiter(5, 100, clock=lambda: now[0])  # auto-registers in the prune registry
    rl.allow('idle-key')
    now[0] = 2000.0  # 1000s later
    rl.allow('fresh-key')  # touched at t=2000
    # Global prune of anything idle > 500s: drops idle-key, keeps fresh-key.
    dropped = prune_idle_buckets(500)
    assert dropped >= 1
    assert 'idle-key' not in rl._buckets
    assert 'fresh-key' in rl._buckets


class _User:
    def __init__(self, uid: str) -> None:
        self.id = uid


async def test_dependency_raises_429_over_limit():
    limit = UserRateLimit('demo', 2, 100, 'slow down')
    limit._limiter._clock = lambda: 0.0  # freeze so nothing refills mid-test
    user = _User('user-1')

    assert await limit(user) is user  # 1st
    assert await limit(user) is user  # 2nd
    with pytest.raises(HTTPException) as exc:
        await limit(user)  # 3rd → blocked
    assert exc.value.status_code == 429
    assert exc.value.detail == 'slow down'

    # A different user is unaffected by user-1 hitting the cap.
    assert await limit(_User('user-2')) is not None
