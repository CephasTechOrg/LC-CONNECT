"""Public health probes for orchestrators (Render, load balancers, k8s).

Split by design:
- ``GET /health`` — **liveness**: process is up. Never touches dependencies.
- ``GET /health/ready`` — **readiness**: can serve traffic (Postgres required;
  Redis probed when ``REDIS_URL`` is set and a client exists).

Admin ``/api/v1/admin/system-status`` remains the richer authenticated dashboard view
(Auth + Storage + DB). These public probes stay minimal and free of PII/secrets.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Literal

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings

logger = logging.getLogger('lc_connect.health')

router = APIRouter(tags=['health'])

CheckStatus = Literal['ok', 'down', 'skipped']
ReadyStatus = Literal['ready', 'not_ready']

# Bound every dependency probe — a hung DB must not hang the readiness endpoint
# (and thus the whole deploy's health check budget).
_PROBE_TIMEOUT_SECONDS = 2.0


class HealthChecks(BaseModel):
    database: CheckStatus
    redis: CheckStatus = Field(
        description='skipped until REDIS_URL is set; then requires a live PING',
    )


class LivenessResponse(BaseModel):
    status: Literal['ok'] = 'ok'
    service: str = 'lc-connect-api'


class ReadinessResponse(BaseModel):
    status: ReadyStatus
    service: str = 'lc-connect-api'
    checks: HealthChecks


async def check_database_session(db: AsyncSession) -> bool:
    """True when ``SELECT 1`` succeeds on an existing session (admin system-status)."""
    try:
        await db.execute(text('SELECT 1'))
        return True
    except Exception:  # noqa: BLE001 — status checks must never raise
        logger.exception('health: database session check failed')
        return False


async def probe_database() -> CheckStatus:
    """Open a short-lived connection from the app pool (independent of request sessions)."""
    from app.database import engine

    async def _ping() -> None:
        async with engine.connect() as conn:
            await conn.execute(text('SELECT 1'))

    try:
        await asyncio.wait_for(_ping(), timeout=_PROBE_TIMEOUT_SECONDS)
        return 'ok'
    except Exception:  # noqa: BLE001
        logger.exception('health: database probe failed')
        return 'down'


async def probe_redis() -> CheckStatus:
    """Unconfigured → skipped. Configured → PING via the shared client (or a one-shot probe)."""
    if not settings.redis_url:
        return 'skipped'

    from app.shared.redis_client import get_redis, ping_redis

    if get_redis() is not None:
        return 'ok' if await ping_redis() else 'down'

    # Lifespan has not connected yet (or connect failed) — one-shot probe for readiness.
    try:
        import redis.asyncio as redis_async
    except ImportError:
        logger.error('health: REDIS_URL is set but redis package is not installed')
        return 'down'

    client = redis_async.from_url(settings.redis_url, socket_connect_timeout=_PROBE_TIMEOUT_SECONDS)

    async def _ping() -> None:
        try:
            await client.ping()
        finally:
            await client.aclose()

    try:
        await asyncio.wait_for(_ping(), timeout=_PROBE_TIMEOUT_SECONDS)
        return 'ok'
    except Exception:  # noqa: BLE001
        logger.exception('health: redis probe failed')
        return 'down'


async def build_readiness() -> ReadinessResponse:
    database = await probe_database()
    redis = await probe_redis()
    # Required: database. Optional: redis (skipped when not configured).
    required_ok = database == 'ok'
    optional_ok = redis in {'ok', 'skipped'}
    ready = required_ok and optional_ok
    return ReadinessResponse(
        status='ready' if ready else 'not_ready',
        checks=HealthChecks(database=database, redis=redis),
    )


@router.get('/health', response_model=LivenessResponse)
async def liveness() -> LivenessResponse:
    """Liveness — the API process is running. Safe for frequent cheap probes."""
    return LivenessResponse()


@router.get('/health/ready', response_model=ReadinessResponse)
async def readiness() -> JSONResponse:
    """Readiness — dependencies required to serve traffic are reachable.

    Returns HTTP 503 when not ready so load balancers stop sending traffic.
    """
    report = await build_readiness()
    code = 200 if report.status == 'ready' else 503
    return JSONResponse(status_code=code, content=report.model_dump())
