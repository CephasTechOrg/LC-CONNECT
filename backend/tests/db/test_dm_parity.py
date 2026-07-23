"""DM parity tests — the safety net for the Conversation migration (P0).

These run against a **real Postgres** and lock in today's match-based messaging behaviour:
ordering, keyset pagination, reconnect sync, unread counts, read state, idempotency,
duplicate-DM prevention, and conversation authorization.

After the migration (P2) these exact tests must still pass against the conversation-based
path. That is what "parity" means here — same behaviour, new container.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.features.connections.service import existing_match, ordered_pair
from app.features.messages.router import list_threads
from app.features.messages.service import (
    page_thread,
    persist_message_idempotent,
    sync_thread,
    unread_summary,
)
from app.features.realtime.service import WsForbidden, authorize_conversation, mark_read

BASE = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)


async def _conversation(factory, *, count: int = 0):
    """Two matched users, optionally seeded with `count` alternating messages."""
    alice = await factory.user(display_name='Alice')
    bob = await factory.user(display_name='Bob')
    match = await factory.match(alice, bob)
    messages = []
    for i in range(count):
        sender = alice if i % 2 == 0 else bob
        messages.append(
            await factory.message(match, sender, f'msg-{i}', created_at=BASE + timedelta(minutes=i))
        )
    return alice, bob, match, messages


# ── ordering + pagination ────────────────────────────────────────────────────────

async def test_thread_page_is_newest_first(db, factory):
    _, _, match, messages = await _conversation(factory, count=5)
    page = await page_thread(db, match.id, before_created_at=None, before_id=None, limit=50)
    assert [m.body for m in page] == [m.body for m in reversed(messages)]


async def test_keyset_pagination_has_no_gaps_or_duplicates(db, factory):
    _, _, match, messages = await _conversation(factory, count=10)

    seen: list[str] = []
    cursor = (None, None)
    for _ in range(5):  # 10 messages, 3 per page
        page = await page_thread(
            db, match.id, before_created_at=cursor[0], before_id=cursor[1], limit=3
        )
        if not page:
            break
        seen.extend(m.body for m in page)
        oldest = page[-1]
        cursor = (oldest.created_at, oldest.id)

    assert seen == [m.body for m in reversed(messages)]  # every message, exactly once, in order
    assert len(seen) == len(set(seen))


async def test_sync_returns_only_messages_after_the_cursor_oldest_first(db, factory):
    _, _, match, messages = await _conversation(factory, count=6)
    cursor = messages[2]

    caught_up = await sync_thread(
        db, match.id, after_created_at=cursor.created_at, after_id=cursor.id, limit=100
    )
    assert [m.body for m in caught_up] == [m.body for m in messages[3:]]


# ── unread + read state ──────────────────────────────────────────────────────────

async def test_unread_counts_only_the_partners_unread_messages(db, factory):
    alice, bob, match, _ = await _conversation(factory, count=4)  # alice: 0,2  bob: 1,3

    total_a, per_a = await unread_summary(db, alice.id)
    total_b, per_b = await unread_summary(db, bob.id)

    assert total_a == 2 and per_a == {match.id: 2}  # bob's two messages
    assert total_b == 2 and per_b == {match.id: 2}  # alice's two messages


async def test_mark_read_clears_partner_messages_up_to_cursor_only(db, factory):
    alice, bob, match, messages = await _conversation(factory, count=6)
    # bob reads through message index 3 (alice sent 0, 2, 4)
    read_at = await mark_read(db, reader_id=bob.id, match_id=match.id, through_message_id=messages[3].id)
    assert read_at is not None

    total_b, per_b = await unread_summary(db, bob.id)
    assert total_b == 1  # only alice's msg-4 remains unread
    assert per_b == {match.id: 1}

    # Alice's own view is untouched — reading never marks your own messages.
    total_a, _ = await unread_summary(db, alice.id)
    assert total_a == 3


async def test_mark_read_is_a_noop_for_an_unknown_cursor(db, factory):
    _, bob, match, _ = await _conversation(factory, count=2)
    assert await mark_read(db, reader_id=bob.id, match_id=match.id, through_message_id=uuid4()) is None


# ── idempotency + duplicate DM prevention ────────────────────────────────────────

async def test_duplicate_client_message_id_returns_the_same_row(db, factory):
    alice, bob, match, _ = await _conversation(factory)
    await db.commit()  # persist_message_idempotent manages its own transaction
    client_id = uuid4()

    first, created_first = await persist_message_idempotent(
        db, sender_id=alice.id, match_id=match.id, body='hello', client_message_id=client_id
    )
    second, created_second = await persist_message_idempotent(
        db, sender_id=alice.id, match_id=match.id, body='hello', client_message_id=client_id
    )

    assert created_first is True
    assert created_second is False  # the partial unique index is the arbiter
    assert first.id == second.id  # both acks converge on one server message


async def test_duplicate_dm_is_prevented_by_the_normalized_pair(db, factory):
    alice = await factory.user()
    bob = await factory.user()
    match = await factory.match(alice, bob)

    # Lookup is order-independent, so a "reverse" pair finds the same match.
    assert (await existing_match(db, alice.id, bob.id)).id == match.id
    assert (await existing_match(db, bob.id, alice.id)).id == match.id
    assert ordered_pair(alice.id, bob.id) == ordered_pair(bob.id, alice.id)


# ── conversation authorization ───────────────────────────────────────────────────

async def test_member_may_access_the_conversation(db, factory):
    alice, _, match, _ = await _conversation(factory)
    assert (await authorize_conversation(db, alice.id, match.id)).id == match.id


async def test_non_member_is_forbidden(db, factory):
    _, _, match, _ = await _conversation(factory)
    outsider = await factory.user()
    with pytest.raises(WsForbidden):
        await authorize_conversation(db, outsider.id, match.id)


async def test_unknown_conversation_is_forbidden(db, factory):
    alice = await factory.user()
    with pytest.raises(WsForbidden):
        await authorize_conversation(db, alice.id, uuid4())


async def test_blocked_pair_cannot_access_their_conversation(db, factory):
    alice, bob, match, _ = await _conversation(factory)
    await factory.block(bob, alice)  # either direction blocks both

    with pytest.raises(WsForbidden):
        await authorize_conversation(db, alice.id, match.id)
    with pytest.raises(WsForbidden):
        await authorize_conversation(db, bob.id, match.id)


# ── thread list ──────────────────────────────────────────────────────────────────

async def test_thread_list_is_ordered_by_most_recent_activity(db, factory):
    alice = await factory.user(display_name='Alice')
    bob = await factory.user(display_name='Bob')
    carol = await factory.user(display_name='Carol')

    older = await factory.match(alice, bob)
    newer = await factory.match(alice, carol)
    await factory.message(older, bob, 'older', created_at=BASE)
    await factory.message(newer, carol, 'newer', created_at=BASE + timedelta(hours=1))

    threads = await list_threads(current_user=alice, db=db)
    partners = [t.partner.display_name for t in threads]

    assert set(partners) == {'Bob', 'Carol'}
    assert {t.match_id for t in threads} == {older.id, newer.id}
    latest = {t.match_id: (t.latest_message.body if t.latest_message else None) for t in threads}
    assert latest == {older.id: 'older', newer.id: 'newer'}
