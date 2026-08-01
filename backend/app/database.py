from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import settings


class Base(DeclarativeBase):
    pass


def _redact(url: str) -> str:
    """`postgresql://user:secret@host/db` -> `postgresql://user:***@host/db`, so a startup error
    can name the problem without ever printing the password into deploy logs."""
    if '@' not in url:
        return url
    creds, _, host = url.rpartition('@')
    scheme, sep, userinfo = creds.rpartition('//')
    if ':' in userinfo:
        user, _, _pw = userinfo.partition(':')
        userinfo = f'{user}:***'
    return f'{scheme}{sep}{userinfo}@{host}'


def _async_url(url: str) -> str:
    """Strip whitespace and ensure the URL uses the postgresql+asyncpg:// scheme.

    Validates up front so a malformed value fails with an actionable message instead of
    SQLAlchemy's opaque "Could not parse SQLAlchemy URL from given URL string" several frames
    deep in an Alembic import — the exact failure this check was added in response to.
    """
    url = url.strip()
    # Quotes are never part of a URL: a shell/dashboard value pasted with them wrapped around it.
    if len(url) >= 2 and url[0] == url[-1] and url[0] in '"\'':
        url = url[1:-1].strip()

    if not url:
        raise ValueError('DATABASE_URL is empty. Set it to your Postgres connection string.')
    if any(token in url for token in ('[YOUR-PASSWORD]', '[YOUR_PASSWORD]', 'YOUR-PASSWORD')):
        raise ValueError(
            'DATABASE_URL still contains the placeholder password from the Supabase dashboard. '
            'Replace [YOUR-PASSWORD] with your real database password.'
        )
    if not url.startswith(('postgresql://', 'postgres://', 'postgresql+asyncpg://')):
        raise ValueError(
            'DATABASE_URL must start with postgresql:// (or postgres://). '
            f'Got: {_redact(url)[:60]!r}'
        )

    for prefix in ('postgresql://', 'postgres://'):
        if url.startswith(prefix):
            return 'postgresql+asyncpg://' + url[len(prefix) :]
    return url


def _is_local(url: str) -> bool:
    return 'localhost' in url or '127.0.0.1' in url


_db_url = _async_url(settings.database_url)

# Transaction pooler (port 6543) requires SSL and no prepared statements.
# Local connections need neither.
_connect_args = (
    {}
    if _is_local(_db_url)
    else {'ssl': 'require', 'statement_cache_size': 0}
)

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
