"""Messages service: idempotency contract + keyset-pagination direction guards.

DB-free by design (the suite has no live Postgres). Idempotency is tested via a
mocked session that drives the IntegrityError/rollback/re-select control flow, and
paging direction is asserted against the *compiled SQL* — the cheap, deterministic
way to catch the classic keyset bugs (``<`` vs ``>``, ``ASC`` vs ``DESC``) without a
database.
"""

from __future__ import annotations

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy.dialects import postgresql
from sqlalchemy.exc import IntegrityError

from app.features.messages.service import (
    get_match_for_user,
    page_thread,
    partner_id,
    persist_message_idempotent,
    sync_thread,
)
from app.models import Match, Message


class _User:
    def __init__(self, uid=None):
        self.id = uid or uuid4()


def _integrity_error() -> IntegrityError:
    return IntegrityError('INSERT ...', {}, Exception('duplicate key'))


# ── partner_id / get_match_for_user ────────────────────────────────────────────

def test_partner_id_returns_the_other_member():
    a, b = _User(), _User()
    match = Match(user_a_id=a.id, user_b_id=b.id)
    assert partner_id(match, a) == b.id
    assert partner_id(match, b) == a.id


async def test_get_match_for_user_404_when_missing():
    db = MagicMock()
    db.get = AsyncMock(return_value=None)
    with pytest.raises(HTTPException) as exc:
        await get_match_for_user(db, uuid4(), _User())
    assert exc.value.status_code == 404


async def test_get_match_for_user_404_when_not_a_member():
    outsider = _User()
    match = Match(user_a_id=uuid4(), user_b_id=uuid4())
    db = MagicMock()
    db.get = AsyncMock(return_value=match)
    with pytest.raises(HTTPException) as exc:
        await get_match_for_user(db, uuid4(), outsider)
    assert exc.value.status_code == 404


async def test_get_match_for_user_returns_match_for_member():
    member = _User()
    match = Match(user_a_id=member.id, user_b_id=uuid4())
    db = MagicMock()
    db.get = AsyncMock(return_value=match)
    assert await get_match_for_user(db, uuid4(), member) is match


# ── idempotency contract ───────────────────────────────────────────────────────

async def test_persist_creates_on_clean_insert():
    db = MagicMock()
    db.add = MagicMock()
    db.flush = AsyncMock()
    db.commit = AsyncMock()
    db.refresh = AsyncMock()
    db.rollback = AsyncMock()

    msg, created = await persist_message_idempotent(
        db, sender_id=uuid4(), match_id=uuid4(), body='hi', client_message_id=uuid4()
    )

    assert created is True
    assert isinstance(msg, Message)
    db.commit.assert_awaited_once()
    db.refresh.assert_awaited_once()
    db.rollback.assert_not_awaited()


async def test_persist_returns_existing_row_on_conflict():
    """A duplicate client_message_id must roll back and return the original row
    (created=False) so both the retry and the original ack converge on one id."""
    existing = Message(sender_id=uuid4(), match_id=uuid4(), body='hi')
    result = MagicMock()
    result.scalar_one.return_value = existing

    db = MagicMock()
    db.add = MagicMock()
    db.flush = AsyncMock(side_effect=_integrity_error())
    db.rollback = AsyncMock()
    db.commit = AsyncMock()
    db.execute = AsyncMock(return_value=result)

    msg, created = await persist_message_idempotent(
        db, sender_id=existing.sender_id, match_id=existing.match_id, body='hi',
        client_message_id=uuid4(),
    )

    assert created is False
    assert msg is existing
    db.rollback.assert_awaited_once()
    db.commit.assert_not_awaited()  # never commit on the conflict path


# ── keyset direction guards (compiled SQL) ─────────────────────────────────────

async def _capture_stmt(coro_factory):
    """Run a service fn with a session that records the executed statement."""
    captured: dict = {}

    async def fake_execute(stmt):
        captured['stmt'] = stmt
        result = MagicMock()
        result.scalars.return_value.all.return_value = []
        return result

    db = MagicMock()
    db.execute = fake_execute
    await coro_factory(db)
    return str(captured['stmt'].compile(dialect=postgresql.dialect()))


async def test_page_thread_is_newest_first_with_backward_cursor():
    now = datetime.now(UTC)
    sql = await _capture_stmt(
        lambda db: page_thread(db, uuid4(), before_created_at=now, before_id=uuid4(), limit=50)
    )
    assert 'ORDER BY messages.created_at DESC, messages.id DESC' in sql
    assert ') < (' in sql  # keyset scans strictly *older* than the cursor
    assert 'LIMIT' in sql


async def test_page_thread_first_page_has_no_cursor_predicate():
    sql = await _capture_stmt(
        lambda db: page_thread(db, uuid4(), before_created_at=None, before_id=None, limit=50)
    )
    assert ') < (' not in sql  # no cursor supplied → plain newest page
    assert 'ORDER BY messages.created_at DESC, messages.id DESC' in sql


async def test_sync_thread_is_oldest_first_with_forward_cursor():
    now = datetime.now(UTC)
    sql = await _capture_stmt(
        lambda db: sync_thread(db, uuid4(), after_created_at=now, after_id=uuid4(), limit=100)
    )
    assert 'ORDER BY messages.created_at ASC, messages.id ASC' in sql
    assert ') > (' in sql  # catch-up scans strictly *newer* than the cursor
