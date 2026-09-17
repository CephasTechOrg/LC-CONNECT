"""Bring the database to the current schema, whatever state it is in, then seed lookup data.

The single entry point for schema setup — used by the deploy start command and by local setup.

**Why this exists.** `alembic upgrade head` cannot build this database from empty. The initial
revision (`3ffad56200ff`) does not define the schema column by column: it inspects the database and,
on a fresh one, calls `Base.metadata.create_all`, which builds the **current** models. Alembic then
replays the 38 later revisions on top of a schema that already has everything, and 33 of those are
unguarded `ALTER`s — so the second revision fails with `DuplicateColumnError` and the deploy dies.

The adaptive initial revision was the right instinct; it was simply never finished. "Fresh database
gets the current schema" has to be paired with "and is recorded as already at head", or Alembic
tries to migrate it forward from the beginning. That pairing is what this script adds.

So there are exactly two paths, chosen by inspection rather than by a flag someone has to remember:

  * **empty** → `create_all` + `alembic stamp head`. Skipping the historical revisions is correct,
    not a shortcut: every one of them either reshapes a table the models already describe, or
    backfills rows that do not exist yet.
  * **already managed** → `alembic upgrade head`, the normal incremental path.

A third state — tables present but no `alembic_version` — is **refused** rather than guessed at.
Either choice could be wrong there, and both are destructive in a different way.

Squashing the chain into a real baseline is the proper long-term fix; see
`docs/reviews/BETA_FEEDBACK_REVIEW.md` finding 18. This script makes a new environment buildable
today without rewriting 38 revisions or touching production's `alembic_version`.
"""

from __future__ import annotations

import asyncio
import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from enum import Enum
from pathlib import Path

from alembic.config import Config
from sqlalchemy import inspect
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from alembic import command

# `scripts/` is not a package; the repo root has to be importable for `app.*`.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import models  # noqa: E402, F401 — registers every model with the metadata
from app.config import settings  # noqa: E402
from app.database import Base  # noqa: E402
from app.seed import seed_lookup_data  # noqa: E402

# Presence of this table means Alembic owns the schema.
_VERSION_TABLE = 'alembic_version'
# Any app table would do; `users` is the oldest and can never legitimately be absent.
_SENTINEL_TABLE = 'users'


class DbState(Enum):
    EMPTY = 'empty'
    MANAGED = 'managed'
    UNMANAGED_SCHEMA = 'unmanaged_schema'


def _alembic_config() -> Config:
    """Resolved from this file, not the working directory, so the deploy's cwd cannot matter."""
    return Config(str(Path(__file__).resolve().parent.parent / 'alembic.ini'))


@asynccontextmanager
async def _own_engine() -> AsyncIterator[AsyncEngine]:
    """A private engine for one step, disposed when the step ends.

    Deliberately not `app.database.engine`: a connection pool binds to the event loop that first
    used it, and each step here runs in its own `asyncio.run` (see [main]). Sharing the module
    engine across them fails with "attached to a different loop". `NullPool` because a one-shot
    script has nothing to pool.
    """
    engine = create_async_engine(settings.database_url, poolclass=NullPool)
    try:
        yield engine
    finally:
        await engine.dispose()


async def _detect_state() -> DbState:
    async with _own_engine() as engine, engine.connect() as conn:
        tables = await conn.run_sync(lambda sync_conn: set(inspect(sync_conn).get_table_names()))
    if _VERSION_TABLE in tables:
        return DbState.MANAGED
    if _SENTINEL_TABLE in tables:
        return DbState.UNMANAGED_SCHEMA
    return DbState.EMPTY


async def _create_schema() -> None:
    async with _own_engine() as engine, engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def _seed() -> None:
    async with _own_engine() as engine:
        session_factory = async_sessionmaker(bind=engine, expire_on_commit=False)
        async with session_factory() as db:
            await seed_lookup_data(db)


def main() -> int:
    # Each step gets its own event loop on purpose. Alembic's `env.py` calls `asyncio.run` itself
    # (`run_migrations_online`), so invoking `command.upgrade` from inside a running loop raises
    # "cannot be called from a running event loop". Sequencing separate loops keeps that honest
    # instead of papering over it with nest_asyncio.
    state = asyncio.run(_detect_state())
    config = _alembic_config()

    if state is DbState.UNMANAGED_SCHEMA:
        print(
            f'ERROR: found application tables but no `{_VERSION_TABLE}`.\n'
            '\n'
            'This database has a schema that Alembic does not know about, and guessing would be\n'
            'destructive either way — stamping could mark missing changes as applied, while\n'
            'migrating could fail halfway. Resolve it deliberately:\n'
            '\n'
            '  * if the schema is already current:  alembic stamp head\n'
            '  * if it predates Alembic:            stamp the revision it actually matches\n'
            '  * if it is a scratch database:       drop it and re-run this script\n',
            file=sys.stderr,
        )
        return 1

    if state is DbState.EMPTY:
        print('empty database — creating the schema from the models')
        asyncio.run(_create_schema())
        # Records the schema as current so later deploys take the incremental path. Without this
        # the next `upgrade head` would try to replay history over a finished schema.
        command.stamp(config, 'head')
        print('schema created and stamped at head')
    else:
        print('existing database — applying any outstanding migrations')
        command.upgrade(config, 'head')
        print('migrations up to date')

    asyncio.run(_seed())
    print('lookup data seeded')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
