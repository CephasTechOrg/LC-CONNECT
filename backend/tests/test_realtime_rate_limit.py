"""Token-bucket rate limiter — deterministic via an injected clock."""

from app.features.realtime.rate_limit import RateLimiter


class FakeClock:
    def __init__(self) -> None:
        self.t = 0.0

    def __call__(self) -> float:
        return self.t


def test_allows_up_to_capacity_then_blocks():
    clock = FakeClock()
    limiter = RateLimiter(capacity=3, per_seconds=10, clock=clock)
    assert [limiter.allow('k') for _ in range(4)] == [True, True, True, False]


def test_refills_over_time():
    clock = FakeClock()
    limiter = RateLimiter(capacity=2, per_seconds=10, clock=clock)  # 0.2 tokens/sec
    assert limiter.allow('k') and limiter.allow('k')
    assert not limiter.allow('k')
    clock.t = 5.0  # +1 token
    assert limiter.allow('k')
    assert not limiter.allow('k')


def test_keys_are_independent():
    limiter = RateLimiter(capacity=1, per_seconds=10, clock=FakeClock())
    assert limiter.allow('a')
    assert limiter.allow('b')
    assert not limiter.allow('a')


def test_discard_and_prune():
    clock = FakeClock()
    limiter = RateLimiter(capacity=1, per_seconds=10, clock=clock)
    limiter.allow('a')
    limiter.allow('b')
    assert len(limiter) == 2
    limiter.discard('a')
    assert len(limiter) == 1
    clock.t = 100.0
    limiter.allow('c')  # fresh, recent
    assert limiter.prune(idle_seconds=50) == 1  # 'b' is stale, 'c' is not
    assert len(limiter) == 1
