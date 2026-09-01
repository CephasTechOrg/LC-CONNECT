"""Ephemeral QR challenge storage — Redis when available, in-process fallback for tests/dev."""

from __future__ import annotations

import logging
import time
from uuid import UUID

from app.config import settings
from app.shared.redis_client import get_redis

logger = logging.getLogger('lc_connect.attendance')

# session_id:challenge_id -> monotonic expiry (fallback when Redis is unset).
_memory: dict[str, float] = {}


def _key(session_id: UUID, challenge_id: UUID) -> str:
    return f'attendance:challenge:{session_id}:{challenge_id}'


def _redis_key(session_id: UUID, challenge_id: UUID) -> str:
    return f'lcconnect:{settings.environment_slug}:{_key(session_id, challenge_id)}'


def _purge_memory() -> None:
    now = time.monotonic()
    stale = [k for k, exp in _memory.items() if exp <= now]
    for key in stale:
        del _memory[key]


async def store_challenge(*, session_id: UUID, challenge_id: UUID, ttl_seconds: int) -> None:
    client = get_redis()
    if client is not None:
        try:
            await client.set(_redis_key(session_id, challenge_id), '1', ex=max(1, ttl_seconds))
            return
        except Exception:  # noqa: BLE001 — fall back to memory for resilience
            logger.warning('attendance: redis challenge store failed — memory fallback', exc_info=True)

    _purge_memory()
    _memory[_key(session_id, challenge_id)] = time.monotonic() + ttl_seconds


async def challenge_exists(*, session_id: UUID, challenge_id: UUID) -> bool:
    client = get_redis()
    if client is not None:
        try:
            return bool(await client.exists(_redis_key(session_id, challenge_id)))
        except Exception:  # noqa: BLE001
            logger.warning('attendance: redis challenge lookup failed — memory fallback', exc_info=True)

    _purge_memory()
    return _memory.get(_key(session_id, challenge_id), 0) > time.monotonic()


async def clear_session_challenges(session_id: UUID) -> None:
    """Best-effort cleanup when a session closes (Redis keys also expire via TTL)."""
    prefix = f'attendance:challenge:{session_id}:'
    stale = [k for k in _memory if k.startswith(prefix)]
    for key in stale:
        del _memory[key]

    client = get_redis()
    if client is None:
        return
    try:
        pattern = f'lcconnect:{settings.environment_slug}:{prefix}*'
        async for key in client.scan_iter(match=pattern, count=50):
            await client.delete(key)
    except Exception:  # noqa: BLE001
        logger.warning('attendance: redis challenge cleanup failed', exc_info=True)


def reset_memory_store_for_tests() -> None:
    _memory.clear()
