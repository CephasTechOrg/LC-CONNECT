from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


class Base(DeclarativeBase):
    pass


def _async_url(url: str) -> str:
    """Ensure the URL uses the postgresql+asyncpg:// scheme."""
    for prefix in ('postgresql://', 'postgres://'):
        if url.startswith(prefix):
            return 'postgresql+asyncpg://' + url[len(prefix):]
    return url


def _is_local(url: str) -> bool:
    return 'localhost' in url or '127.0.0.1' in url


_db_url = _async_url(settings.database_url)
_connect_args = {} if _is_local(_db_url) else {'ssl': 'require'}

engine = create_async_engine(
    _db_url,
    echo=False,
    pool_pre_ping=True,
    connect_args=_connect_args,
)
AsyncSessionLocal = async_sessionmaker(bind=engine, class_=AsyncSession, expire_on_commit=False, autoflush=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
