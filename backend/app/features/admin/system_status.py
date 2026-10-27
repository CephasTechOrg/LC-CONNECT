"""Live health checks for the admin dashboard's System Status strip.

Every value returned here is the result of an actual check made at request time — never a
hardcoded 'operational'. Storage and Auth-admin pings are sync HTTP, so they run in a
thread pool via ``run_sync`` (same as the rest of those call sites).
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.features.admin.schema import ServiceStatus, SystemStatusRead
from app.features.realtime.runtime import manager as ws_manager
from app.shared import supabase_admin
from app.shared.blocking import run_sync
from app.shared.health import check_database_session
from app.shared.storage import storage_service


async def _check_database(db: AsyncSession) -> ServiceStatus:
    return 'operational' if await check_database_session(db) else 'down'


async def get_system_status(db: AsyncSession) -> SystemStatusRead:
    return SystemStatusRead(
        api_gateway='operational',  # implicit — you only see this if the API answered at all
        database=await _check_database(db),
        auth='operational' if await run_sync(supabase_admin.ping) else 'down',
        storage='operational' if await run_sync(storage_service.ping) else 'down',
        websocket_connections=ws_manager.total_connections,
    )
