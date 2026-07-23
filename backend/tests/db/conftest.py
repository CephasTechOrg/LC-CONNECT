"""Postgres integration-test harness (P0 of the groups plan).

The rest of the suite is deliberately DB-free — it proves the API contract and isolated
logic, but **not** that messaging behaves correctly on real rows. These fixtures give the
*parity* tests a real Postgres so we can lock messaging behaviour in place **before** the
Conversation migration moves the message container.

Safety:
- Uses a **separate database** (default `lc_connect_test`, auto-created) — never the dev DB.
  Override with ``TEST_DATABASE_URL``.
- Every test starts from a truncated schema, so tests never see each other's rows.
- If Postgres isn't reachable the DB tests **skip cleanly**, so the DB-free suite still runs
  everywhere (including CI without a database).
"""

from __future__ import annotations

import os
from datetime import datetime
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4

import pytest
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

import app.models  # noqa: F401  — imported so Base.metadata is fully populated
from app.config import settings
from app.database import Base, _async_url
from app.features.connections.service import ordered_pair
from app.models import Block, Conversation, Match, Message, Profile, User
from app.shared.conversations import ensure_dm_conversation

TEST_DB_NAME = 'lc_connect_test'


def test_database_url() -> str:
    override = os.getenv('TEST_DATABASE_URL')
    if override:
        return _async_url(override)
    parts = urlsplit(_async_url(settings.database_url))
    return urlunsplit(parts._replace(path=f'/{TEST_DB_NAME}'))


async def _ensure_database(url: str) -> None:
    """Create the test database if it doesn't exist yet (zero-setup for contributors)."""
    parts = urlsplit(url)
    dbname = parts.path.lstrip('/')
    admin_url = urlunsplit(parts._replace(path='/postgres'))
    engine = create_async_engine(admin_url, isolation_level='AUTOCOMMIT', poolclass=NullPool)
    try:
        async with engine.connect() as conn:
            exists = (
                await conn.execute(text('SELECT 1 FROM pg_database WHERE datname = :n'), {'n': dbname})
            ).scalar()
            if not exists:
                await conn.execute(text(f'CREATE DATABASE "{dbname}"'))
    finally:
        await engine.dispose()


# Rebuild the schema once per pytest session so it always matches the models
# (`create_all` alone never ALTERs an existing table, so added columns would be missed).
_SCHEMA_REBUILT = False


async def _prepare_schema(engine) -> None:
    global _SCHEMA_REBUILT
    async with engine.begin() as conn:
        if not _SCHEMA_REBUILT:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)
            _SCHEMA_REBUILT = True
            return
        tables = ', '.join(f'"{t.name}"' for t in Base.metadata.sorted_tables)
        await conn.execute(text(f'TRUNCATE {tables} RESTART IDENTITY CASCADE'))


@pytest_asyncio.fixture
async def _engine():
    """A clean test-DB engine (NullPool, so concurrent sessions each get their own
    connection — needed for the capacity race test). Skips if Postgres isn't available."""
    url = test_database_url()
    engine = None
    try:
        await _ensure_database(url)
        engine = create_async_engine(url, poolclass=NullPool)
        await _prepare_schema(engine)
    except Exception as exc:  # noqa: BLE001 — any connectivity/permission problem → skip
        if engine is not None:
            await engine.dispose()
        pytest.skip(f'Postgres test DB unavailable ({type(exc).__name__}: {exc}) — skipping DB tests')
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture
async def db(_engine) -> AsyncSession:
    """A session against a clean test database."""
    session_factory = async_sessionmaker(
        bind=_engine, class_=AsyncSession, expire_on_commit=False, autoflush=False
    )
    async with session_factory() as session:
        yield session


@pytest_asyncio.fixture
def sessions(_engine):
    """Factory for *additional* independent sessions on the same test DB — for concurrency
    tests where two transactions must contend (e.g. simultaneous group joins)."""
    return async_sessionmaker(bind=_engine, class_=AsyncSession, expire_on_commit=False, autoflush=False)


@pytest_asyncio.fixture
async def factory(db: AsyncSession):
    """Builders for the rows these tests need."""
    return _Factory(db)


class _Factory:
    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def user(self, *, display_name: str = 'Student', is_verified: bool = True) -> User:
        user = User(email=f'{uuid4().hex[:10]}@livingstone.edu', is_verified=is_verified)
        self.db.add(user)
        await self.db.flush()
        self.db.add(Profile(user_id=user.id, display_name=display_name, profile_completed=True))
        await self.db.flush()
        return user

    async def match(self, user_a: User, user_b: User) -> Match:
        """Create a match the way production does — normalized pair + its DM conversation."""
        left, right = ordered_pair(user_a.id, user_b.id)
        match = Match(user_a_id=left, user_b_id=right)
        self.db.add(match)
        await self.db.flush()
        await ensure_dm_conversation(self.db, match)
        return match

    async def conversation(self, match: Match) -> Conversation:
        """The match's DM conversation (messaging internals key on this)."""
        return await ensure_dm_conversation(self.db, match)

    async def message(
        self,
        match: Match,
        sender: User,
        body: str,
        *,
        created_at: datetime | None = None,
    ) -> Message:
        """Create a message.

        `created_at` is explicit by default in ordering tests: Postgres ``now()`` is the
        *transaction* timestamp, so rows inserted in one transaction would otherwise share
        an identical created_at and make keyset ordering ambiguous.
        """
        conversation = await ensure_dm_conversation(self.db, match)
        message = Message(
            match_id=match.id, conversation_id=conversation.id, sender_id=sender.id, body=body
        )
        if created_at is not None:
            message.created_at = created_at
        self.db.add(message)
        await self.db.flush()
        await self.db.refresh(message)
        return message

    async def block(self, blocker: User, blocked: User) -> Block:
        block = Block(blocker_id=blocker.id, blocked_id=blocked.id)
        self.db.add(block)
        await self.db.flush()
        return block
