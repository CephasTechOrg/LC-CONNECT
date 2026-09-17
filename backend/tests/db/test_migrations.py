"""Migrations are otherwise untested — this is the only thing that exercises them.

The rest of `tests/db` builds its schema with `Base.metadata.create_all` (see `conftest.py`), so it
proves the **models** are right and says nothing about whether a migration matches them. A revision
that added the wrong column, or whose `downgrade` was never tried, would ship green.

That gap is how the chain reached its current state, where `alembic upgrade head` cannot build the
database from empty at all (see `docs/reviews/BETA_FEEDBACK_REVIEW.md` finding 18). These tests
don't fix the history — repairing it is a separate, deliberate job — but they stop it getting
worse, and they check the two things that actually protect a deploy:

  1. the bootstrap path a new environment uses produces a schema that matches the models, and
  2. the newest revision can be applied **and reversed** without drifting from the models.

Everything runs against its own throwaway database so the main test DB is never touched.
"""

from __future__ import annotations

import asyncio
import os
import sys
from urllib.parse import urlsplit, urlunsplit

import pytest
import pytest_asyncio
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.pool import NullPool

import app.models  # noqa: F401 — populates Base.metadata
from app.config import settings
from app.database import Base, _async_url

# `tests/db` is not a package, so conftest's helpers cannot be imported from here. These two are
# small enough to restate; they must stay in step with `tests/db/conftest.py`.
TEST_DB_NAME = 'lc_connect_test'


def _require_test_db() -> bool:
    """CI sets REQUIRE_TEST_DB=1 so unavailable Postgres fails instead of skipping."""
    return os.getenv('REQUIRE_TEST_DB', '').strip().lower() in {'1', 'true', 'yes'}


def _base_test_db_url() -> str:
    """Not named `test_*` on purpose — pytest would collect it as a test case."""
    override = os.getenv('TEST_DATABASE_URL')
    if override:
        return _async_url(override)
    parts = urlsplit(_async_url(settings.database_url))
    return urlunsplit(parts._replace(path=f'/{TEST_DB_NAME}'))

# Deliberately separate from `lc_connect_test`: these tests stamp and downgrade, which would
# corrupt the schema every other DB test depends on.
MIGRATION_DB_NAME = 'lc_connect_migration_test'

# Differences `compare_metadata` reports that are not real drift.
#
# `Base.metadata` does not describe Alembic's own bookkeeping table, so a freshly stamped database
# always appears to have one "extra" table. Nothing else is filtered — the point of this test is to
# notice everything else.
_IGNORED_TABLES = {'alembic_version'}


def _repo_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _history_config() -> Config:
    """Config for the revision-graph checks only. Never used to run a migration."""
    return Config(os.path.join(_repo_root(), 'alembic.ini'))


async def _alembic(url: str, *args: str) -> None:
    """Run an Alembic command in a subprocess against `url`.

    A subprocess, not an in-process `command.*` call, and the reason matters. `alembic/env.py`
    ignores whatever `sqlalchemy.url` the caller sets and overwrites it with
    `settings.database_url` — and `settings` is an `lru_cache`d singleton built at import time. So
    setting `os.environ['DATABASE_URL']` from inside the test process has **no effect**: the
    command runs against whatever database the developer's `.env` points at.

    That is not a hypothetical. Writing this test the obvious way silently stamped and downgraded
    the local dev database, leaving its `alembic_version` one revision ahead of its actual schema.
    A fresh process rebuilds `settings` from the environment, which is also exactly how the deploy
    invokes Alembic — so this exercises the real path rather than a lookalike.
    """
    proc = await asyncio.create_subprocess_exec(
        sys.executable,
        '-m',
        'alembic',
        *args,
        cwd=_repo_root(),
        env={**os.environ, 'DATABASE_URL': url},
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    output, _ = await proc.communicate()
    assert proc.returncode == 0, (
        f'alembic {" ".join(args)} failed:\n{output.decode(errors="replace")}'
    )


def _migration_db_url() -> str:
    """The throwaway database, alongside the normal test database on the same server."""
    parts = urlsplit(_async_url(_base_test_db_url()))
    return urlunsplit(parts._replace(path=f'/{MIGRATION_DB_NAME}'))


async def _recreate_database(url: str) -> None:
    """Drop and recreate the throwaway database, so every run starts from truly empty."""
    parts = urlsplit(url)
    dbname = parts.path.lstrip('/')
    admin = create_async_engine(
        urlunsplit(parts._replace(path='/postgres')),
        isolation_level='AUTOCOMMIT',
        poolclass=NullPool,
    )
    try:
        async with admin.connect() as conn:
            await conn.execute(text(f'DROP DATABASE IF EXISTS "{dbname}" WITH (FORCE)'))
            await conn.execute(text(f'CREATE DATABASE "{dbname}"'))
    finally:
        await admin.dispose()


@pytest_asyncio.fixture
async def migration_db():
    """An empty throwaway database and its URL. Recreated before and after each test."""
    url = _migration_db_url()
    # Belt and braces: these tests stamp and downgrade, so pointing them at anything but the
    # throwaway database would corrupt it. Assert rather than trust the URL construction above.
    assert url.rsplit('/', 1)[-1] == MIGRATION_DB_NAME, f'refusing to migrate {url!r}'

    try:
        await _recreate_database(url)
    except Exception as exc:  # noqa: BLE001 — connectivity or permissions
        detail = f'Postgres unavailable for migration tests ({type(exc).__name__}: {exc})'
        if _require_test_db():
            pytest.fail(f'{detail} — REQUIRE_TEST_DB=1 so this is a hard failure')
        pytest.skip(detail)

    engine = create_async_engine(url, poolclass=NullPool)
    try:
        yield engine, url
    finally:
        await engine.dispose()
        try:
            await _recreate_database(url)  # leave nothing behind
        except Exception:  # noqa: BLE001 — cleanup must never fail a passing run
            pass


async def _schema_differences(engine) -> list:
    """What `compare_metadata` sees between the live schema and the models."""

    def _compare(sync_conn):
        context = MigrationContext.configure(sync_conn)
        return compare_metadata(context, Base.metadata)

    async with engine.connect() as conn:
        diffs = await conn.run_sync(_compare)

    def is_noise(diff) -> bool:
        # ('remove_table', Table(...)) for alembic_version, which the models never describe.
        if isinstance(diff, tuple) and len(diff) == 2 and diff[0] in {'add_table', 'remove_table'}:
            return getattr(diff[1], 'name', None) in _IGNORED_TABLES
        return False

    return [d for d in diffs if not is_noise(d)]


# ── history shape ─────────────────────────────────────────────────────────────────

def test_the_revision_history_has_exactly_one_head():
    """Two heads mean a merge was missed, and `upgrade head` then becomes ambiguous.

    Needs no database — it reads the revision files.
    """
    script = ScriptDirectory.from_config(_history_config())
    heads = script.get_heads()
    assert len(heads) == 1, f'expected a single head, found {heads}'


def test_every_revision_is_reachable_from_the_head():
    """A revision whose `down_revision` points nowhere would silently never run."""
    script = ScriptDirectory.from_config(_history_config())
    head = script.get_heads()[0]
    reachable = {rev.revision for rev in script.walk_revisions('base', head)}
    all_revisions = {rev.revision for rev in script.walk_revisions()}
    assert all_revisions == reachable, f'unreachable revisions: {all_revisions - reachable}'


# ── the bootstrap path a new environment actually uses ────────────────────────────

async def test_bootstrap_produces_a_schema_that_matches_the_models(migration_db):
    """`create_all` + `stamp head` — the path `scripts/bootstrap_db.py` takes on an empty database.

    Asserting there is no drift is what makes that path trustworthy: it is the only way a new
    environment gets built, so if the models and the stamped version ever disagree, every fresh
    environment starts subtly wrong.
    """
    engine, url = migration_db

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await _alembic(url, 'stamp', 'head')

    diffs = await _schema_differences(engine)
    assert diffs == [], f'bootstrapped schema differs from the models: {diffs}'


async def test_bootstrap_records_the_current_head(migration_db):
    engine, url = migration_db
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await _alembic(url, 'stamp', 'head')

    script = ScriptDirectory.from_config(_history_config())
    async with engine.connect() as conn:
        stamped = (await conn.execute(text('SELECT version_num FROM alembic_version'))).scalar()
    assert stamped == script.get_heads()[0]


# ── the newest revision, up and back down ─────────────────────────────────────────

async def test_head_revision_downgrades_and_reapplies_without_drift(migration_db):
    """The newest migration must be reversible and must agree with the models.

    Starting state is the models' schema stamped at head — i.e. the post-migration state, which is
    what a deployed database looks like. Then:

      downgrade -1  → exercises the newest revision's `downgrade()`
      upgrade head  → exercises its `upgrade()`

    and the schema must match the models again. That catches the two failures this suite could not
    see before: an `upgrade()` that does something other than what the models declare, and a
    `downgrade()` that was never run once.
    """
    engine, url = migration_db

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    await _alembic(url, 'stamp', 'head')

    script = ScriptDirectory.from_config(_history_config())
    head = script.get_heads()[0]
    previous = script.get_revision(head).down_revision
    if previous is None:
        pytest.skip('head is the base revision — nothing to downgrade to')

    await _alembic(url, 'downgrade', '-1')
    async with engine.connect() as conn:
        at = (await conn.execute(text('SELECT version_num FROM alembic_version'))).scalar()
    assert at == previous, 'downgrade did not land on the previous revision'

    await _alembic(url, 'upgrade', 'head')
    async with engine.connect() as conn:
        at = (await conn.execute(text('SELECT version_num FROM alembic_version'))).scalar()
    assert at == head

    diffs = await _schema_differences(engine)
    assert diffs == [], f'schema drifted after downgrade+upgrade of {head}: {diffs}'
