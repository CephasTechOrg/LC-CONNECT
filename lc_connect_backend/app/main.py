from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import ORJSONResponse

from app.config import settings
from app.routers import activities, admin, auth, connections, discovery, lookups, messages, profiles, safety

app = FastAPI(title=settings.app_name, version='0.1.0', default_response_class=ORJSONResponse)

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


@app.get('/')
async def root() -> dict[str, str]:
    return {'message': 'LC Connect API is running', 'docs': '/docs'}


@app.get('/health')
async def health_check() -> dict[str, str]:
    return {'status': 'ok', 'service': 'lc-connect-api'}


app.include_router(auth.router, prefix=settings.api_v1_prefix)
app.include_router(lookups.router, prefix=settings.api_v1_prefix)
app.include_router(profiles.router, prefix=settings.api_v1_prefix)
app.include_router(discovery.router, prefix=settings.api_v1_prefix)
app.include_router(connections.router, prefix=settings.api_v1_prefix)
app.include_router(messages.router, prefix=settings.api_v1_prefix)
app.include_router(activities.router, prefix=settings.api_v1_prefix)
app.include_router(safety.router, prefix=settings.api_v1_prefix)
app.include_router(admin.router, prefix=settings.api_v1_prefix)
