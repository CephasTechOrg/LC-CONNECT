"""Process-wide async Redis client.

``REDIS_URL`` unset → no client (single-instance memory paths keep working).
When set, lifespan connects once; Pub/Sub fan-out and distributed rate limits share it.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from app.config import settings

if TYPE_CHECKING:
    from redis.asyncio import Redis

logger = logging.getLogger('lc_connect.redis')

_client: Redis | None = None


def get_redis() -> Redis | None:
    """Return the shared client, or ``None`` when Redis is not configured/connected."""
    return _client


def redis_configured() -> bool:
    return bool(settings.redis_url)


async def connect_redis() -> Redis | None:
    """Open the shared client when ``REDIS_URL`` is set. Idempotent."""
    global _client
    if _client is not None:
        return _client
    if not settings.redis_url:
        logger.info('redis: REDIS_URL unset — using in-memory EventBus + rate limits')
        return None

    from redis.asyncio import from_url

    client = from_url(
        settings.redis_url,
        encoding='utf-8',
        decode_responses=True,
        socket_connect_timeout=2.0,
        socket_timeout=2.0,
    )
    await client.ping()
    _client = client
    logger.info('redis: connected (%s)', settings.environment_slug)
    return _client


async def close_redis() -> None:
    global _client
    if _client is None:
        return
    try:
        await _client.aclose()
    except Exception:  # noqa: BLE001 — shutdown must not raise
        logger.warning('redis: close failed', exc_info=True)
    _client = None


async def ping_redis() -> bool:
    """True when a live client responds to PING."""
    client = _client
    if client is None:
        return False
    try:
        return bool(await client.ping())
    except Exception:  # noqa: BLE001
        return False
