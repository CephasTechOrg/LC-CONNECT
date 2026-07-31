"""Live health checks for the admin dashboard's System Status strip.

Every value returned here is the result of an actual check made at request time — never a
hardcoded 'operational'. Blocking Supabase calls, same as the rest of this codebase's
storage/auth-admin call sites (`app/shared/storage.py`, `app/shared/supabase_admin.py`) — not
wrapped in a thread pool, consistent with the existing convention rather than a new one here.
"""

from __future__ import annotations

import logging

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.admin.schema import ServiceStatus, SystemStatusRead
from app.shared import supabase_admin
from app.shared.storage import storage_service

logger = logging.getLogger(__name__)


async def _check_database(db: AsyncSession) -> ServiceStatus:
    try:
        await db.execute(text('SELECT 1'))
        return 'operational'
    except Exception:  # noqa: BLE001 — a status check must never itself raise
        logger.exception('system_status: database check failed')
        return 'down'


async def get_system_status(db: AsyncSession) -> SystemStatusRead:
    return SystemStatusRead(
        api_gateway='operational',  # implicit — you only see this if the API answered at all
        database=await _check_database(db),
        auth='operational' if supabase_admin.ping() else 'down',
        storage='operational' if storage_service.ping() else 'down',
    )
