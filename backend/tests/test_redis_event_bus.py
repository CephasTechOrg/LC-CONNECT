"""Redis EventBus + distributed rate-limit unit tests (no live Redis required)."""

from __future__ import annotations

import asyncio
import json
from typing import Any
from uuid import uuid4

import pytest

from app.features.realtime.event_bus import InMemoryEventBus, RedisEventBus, apply_control_event
from app.features.realtime.manager import ConnectionManager
from app.shared import redis_client
from app.shared.rate_limit import RateLimiter


class _FakeSocket:
    def __init__(self) -> None:
        self.sent: list[dict[str, Any]] = []

    async def send_json(self, data: Any) -> None:
        self.sent.append(data)

    async def close(self, code: int = 1000) -> None:
        return None


class _FakeRedis:
    """Minimal async Redis stand-in for publish + eval."""

    def __init__(self) -> None:
        self.published: list[tuple[str, str]] = []
        self._buckets: dict[str, list[float]] = {}

    async def publish(self, channel: str, message: str) -> int:
        self.published.append((channel, message))
        return 1

    async def eval(self, script: str, numkeys: int, *keys_and_args: Any) -> int:
        # Mirror token-bucket enough for aallow tests (ignore script body).
        key = keys_and_args[0]
        capacity = float(keys_and_args[1])
        cost = float(keys_and_args[4])
        tokens, _ts = self._buckets.get(key, [capacity, 0.0])
        if tokens >= cost:
            self._buckets[key] = [tokens - cost, 0.0]
            return 1
        return 0


@pytest.fixture(autouse=True)
def _clear_redis_client():
    redis_client._client = None
    yield
    redis_client._client = None


@pytest.mark.asyncio
async def test_inmemory_control_suspends_local_user():
    manager = ConnectionManager(outbox_max=8)
    bus = InMemoryEventBus(manager)
    sock = _FakeSocket()
    user_id = uuid4()
    conn = manager.register(sock, user_id)
    await asyncio.sleep(0)  # let writer start

    await bus.publish_control({'event': 'user.suspended', 'user_id': str(user_id)})
    await asyncio.sleep(0.05)

    # Socket is closed; frame may not flush (unregister cancels the writer).
    assert manager.user_socket_count(user_id) == 0
    await conn.stop()


@pytest.mark.asyncio
async def test_redis_bus_publishes_envelope_when_client_present():
    manager = ConnectionManager(outbox_max=8)
    bus = RedisEventBus(manager, 'dev')
    fake = _FakeRedis()
    redis_client._client = fake  # type: ignore[assignment]

    conv = uuid4()
    frame = {'type': 'message.created', 'id': '1'}
    await bus.publish_to_conversation(conv, frame)

    assert len(fake.published) == 1
    channel, raw = fake.published[0]
    assert channel == f'lcconnect:dev:conversation:{conv}'
    envelope = json.loads(raw)
    assert envelope['kind'] == 'conversation'
    assert envelope['frame'] == frame


@pytest.mark.asyncio
async def test_redis_bus_falls_back_to_local_without_client():
    manager = ConnectionManager(outbox_max=8)
    bus = RedisEventBus(manager, 'dev')
    sock = _FakeSocket()
    user = uuid4()
    conv = uuid4()
    conn = manager.register(sock, user)
    manager.subscribe(conn, conv)
    await asyncio.sleep(0)

    frame = {'type': 'message.created', 'body': 'hi'}
    await bus.publish_to_conversation(conv, frame)
    await asyncio.sleep(0.05)

    assert any(f.get('type') == 'message.created' for f in sock.sent)
    await conn.stop()


@pytest.mark.asyncio
async def test_apply_control_pair_revoked():
    manager = ConnectionManager(outbox_max=8)
    a, b = uuid4(), uuid4()
    conv = uuid4()
    sa, sb = _FakeSocket(), _FakeSocket()
    ca = manager.register(sa, a)
    cb = manager.register(sb, b)
    manager.subscribe(ca, conv)
    manager.subscribe(cb, conv)
    await asyncio.sleep(0)

    await apply_control_event(
        manager,
        {'event': 'pair.revoked', 'user_a': str(a), 'user_b': str(b)},
    )
    assert manager.conversation_subscriber_count(conv) == 0
    await ca.stop()
    await cb.stop()


@pytest.mark.asyncio
async def test_aallow_uses_redis_when_connected():
    limiter = RateLimiter(2, 10, name='test_dist')
    fake = _FakeRedis()
    redis_client._client = fake  # type: ignore[assignment]

    assert await limiter.aallow('u1')
    assert await limiter.aallow('u1')
    assert not await limiter.aallow('u1')


@pytest.mark.asyncio
async def test_aallow_falls_back_to_memory_without_redis():
    limiter = RateLimiter(1, 10, name='test_mem')
    assert await limiter.aallow('k')
    assert not await limiter.aallow('k')
