"""In-memory token-bucket rate limiter.

O(1) per check. One bucket per key (e.g. (user_id, conversation_id)). The clock is
injectable so tests are deterministic. `discard`/`prune` keep the key space bounded;
the Redis-backed distributed version is a later slice behind the same `allow(key)` API.
"""

from __future__ import annotations

import time
from collections.abc import Callable, Hashable


class RateLimiter:
    def __init__(self, capacity: int, per_seconds: float, clock: Callable[[], float] = time.monotonic) -> None:
        if capacity <= 0 or per_seconds <= 0:
            raise ValueError('capacity and per_seconds must be positive')
        self._capacity = float(capacity)
        self._refill_per_sec = capacity / per_seconds
        self._clock = clock
        # key -> [tokens, last_refill_ts]
        self._buckets: dict[Hashable, list[float]] = {}

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
