"""Presence transitions: online on the first socket, offline only after a grace period, and a
quick reconnect inside the grace is invisible to partners."""

from __future__ import annotations

import asyncio
from uuid import uuid4

import pytest

from app.features.realtime import presence


@pytest.fixture
def world(monkeypatch):
    counts: dict = {}
    published: list[tuple] = []
    writes: list = []

    class _Manager:
        def user_socket_count(self, user_id):
            return counts.get(user_id, 0)

    async def publish(user_id, frame):
        published.append((user_id, frame))

    async def write(user_id, at):
        writes.append(user_id)

    monkeypatch.setattr(presence.rt, 'manager', _Manager())
    monkeypatch.setattr(presence, '_publish', publish)
    monkeypatch.setattr(presence, '_write_last_seen', write)
    monkeypatch.setattr(presence.settings, 'presence_offline_grace_seconds', 0.05)
    monkeypatch.setattr(presence.settings, 'presence_last_seen_write_throttle_seconds', 60)
    presence._pending_offline.clear()
    presence._last_write.clear()
    return counts, published, writes


async def test_first_socket_announces_online(world):
    counts, published, writes = world
    user = uuid4()
    counts[user] = 1
    await presence.on_connect(user)
    assert [f['online'] for _, f in published] == [True]


async def test_a_second_socket_announces_nothing(world):
    counts, published, _ = world
    user = uuid4()
    counts[user] = 2
    await presence.on_connect(user)
    assert published == []


async def test_offline_waits_for_the_grace_period(world):
    counts, published, writes = world
    user = uuid4()
    counts[user] = 0
    presence.on_disconnect(user)
    assert published == []
    await asyncio.sleep(0.12)
    assert [f['online'] for _, f in published] == [False]
    assert user in writes


async def test_a_quick_reconnect_is_invisible(world):
    counts, published, _ = world
    user = uuid4()
    counts[user] = 0
    presence.on_disconnect(user)
    counts[user] = 1
    await presence.on_connect(user)
    await asyncio.sleep(0.12)
    assert published == [], 'partners never saw them leave'


async def test_last_seen_writes_are_throttled(world, monkeypatch):
    counts, _, _ = world
    user = uuid4()
    counts[user] = 1
    calls = []

    async def record(user_id, at):
        calls.append(user_id)
        presence._last_write[user_id] = __import__('time').monotonic()

    monkeypatch.setattr(presence, '_write_last_seen', record)
    await presence.on_connect(user)
    await presence.on_connect(user)
    assert calls == [user]
