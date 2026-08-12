import asyncio
import logging
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import ORJSONResponse

from app.config import settings
from app.features.account import router as account_router
from app.features.activities import router as activities_router
from app.features.admin import router as admin_router
from app.features.auth import router as auth_v2_router
from app.features.campus_hub import router as campus_hub_router
from app.features.campus_positions import router as campus_positions_router
from app.features.connections import router as connections_router
from app.features.discovery import router as discovery_router
from app.features.employers import router as employers_router
from app.features.groups.router import router as groups_router
from app.features.lookups import router as lookups_router
from app.features.messages import router as messages_router
from app.features.notifications import inbox_router as notifications_inbox_router
from app.features.notifications import router as notifications_router
from app.features.profiles import router as profiles_router
from app.features.programs import router as programs_router
from app.features.realtime import router as realtime_router
from app.features.realtime.protocol import CloseCode
from app.features.realtime.runtime import manager as ws_manager
from app.features.safety import router as safety_router
from app.features.scholars import router as scholars_router
from app.shared.rate_limit import prune_idle_buckets
from app.shared.request_limits import MaxBodySizeMiddleware

# Surface our own loggers (push, realtime) in the uvicorn console. Without this,
# `lc_connect.*` INFO logs are swallowed (uvicorn only configures its own loggers).
_app_logger = logging.getLogger('lc_connect')
if not _app_logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(logging.Formatter('%(levelname)s:     [%(name)s] %(message)s'))
    _app_logger.addHandler(_handler)
    _app_logger.setLevel(logging.INFO)
    _app_logger.propagate = False


async def _prune_rate_limiters() -> None:
    """Hourly: drop rate-limiter buckets idle > 1 day so the in-memory dicts never grow without
    bound over a long-running process."""
    while True:
        await asyncio.sleep(3600)
        try:
            removed = prune_idle_buckets(86_400)
            if removed:
                logging.getLogger('lc_connect').info('rate-limit prune: dropped %d idle buckets', removed)
        except Exception:  # noqa: BLE001 - a housekeeping failure must never crash the app
            logging.getLogger('lc_connect').warning('rate-limit prune failed', exc_info=True)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncGenerator[None, None]:
    pruner = asyncio.create_task(_prune_rate_limiters())
    yield
    pruner.cancel()
    # Close live WebSockets cleanly on shutdown/restart (clients reconnect + REST-sync).
    await ws_manager.shutdown(CloseCode.GOING_AWAY)


app = FastAPI(
    title=settings.app_name,
    version='0.1.0',
    default_response_class=ORJSONResponse,
    lifespan=lifespan,
)

if settings.is_development:
    allowed_origins = ['*']
else:
    allowed_origins = settings.cors_origin_list

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

# Reject oversized request bodies at the edge (before buffering). Floored at the image cap + 2 MB
# of multipart headroom so it can never be misconfigured to reject a legitimate avatar upload.
_max_body_mb = max(settings.max_request_body_mb, settings.max_profile_image_mb + 2)
app.add_middleware(MaxBodySizeMiddleware, max_bytes=_max_body_mb * 1024 * 1024)


@app.get('/')
async def root() -> dict[str, str]:
    return {'message': 'LC Connect API is running', 'docs': '/docs'}


@app.get('/health')
async def health_check() -> dict[str, str]:
    return {'status': 'ok', 'service': 'lc-connect-api'}


# Supabase Auth is the ONLY auth path — the legacy custom-password router was removed.
app.include_router(auth_v2_router, prefix=settings.api_v1_prefix)
app.include_router(lookups_router, prefix=settings.api_v1_prefix)
app.include_router(profiles_router, prefix=settings.api_v1_prefix)
app.include_router(campus_positions_router, prefix=settings.api_v1_prefix)
app.include_router(campus_hub_router, prefix=settings.api_v1_prefix)
app.include_router(discovery_router, prefix=settings.api_v1_prefix)
app.include_router(connections_router, prefix=settings.api_v1_prefix)
app.include_router(messages_router, prefix=settings.api_v1_prefix)
app.include_router(activities_router, prefix=settings.api_v1_prefix)
app.include_router(groups_router, prefix=settings.api_v1_prefix)
app.include_router(programs_router, prefix=settings.api_v1_prefix)
app.include_router(scholars_router, prefix=settings.api_v1_prefix)
app.include_router(employers_router, prefix=settings.api_v1_prefix)
app.include_router(safety_router, prefix=settings.api_v1_prefix)
app.include_router(admin_router, prefix=settings.api_v1_prefix)
app.include_router(account_router, prefix=settings.api_v1_prefix)
app.include_router(notifications_router, prefix=settings.api_v1_prefix)
app.include_router(notifications_inbox_router, prefix=settings.api_v1_prefix)
app.include_router(realtime_router, prefix=settings.api_v1_prefix)
