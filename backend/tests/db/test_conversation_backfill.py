"""P1 gate — the DM→Conversation backfill must be exact and idempotent.

Runs the *same* SQL the migration runs (`BACKFILL_STATEMENTS`) against real rows, then
asserts the conversation view matches the match-based view exactly.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import text

from app.features.messages.service import unread_summary
from app.shared.conversation_backfill import BACKFILL_STATEMENTS, READ_BOUNDARY_BACKFILL

BASE = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)


async def _backfill(db):
    for statement in BACKFILL_STATEMENTS:
        await db.execute(text(statement))
    await db.flush()


async def _backfill_read_boundary(db):
    for statement in READ_BOUNDARY_BACKFILL:
        await db.execute(text(statement))
    await db.flush()


async def _seed(factory, *, matches: int = 3, messages_per_match: int = 4):
    """A few matches, each with alternating messages."""
    created = []
    for m in range(matches):
        a = await factory.user(display_name=f'A{m}')
        b = await factory.user(display_name=f'B{m}')
        match = await factory.match(a, b)
        for i in range(messages_per_match):
            await factory.message(
                match, a if i % 2 == 0 else b, f'm{m}-{i}', created_at=BASE + timedelta(minutes=i)
            )
        created.append((a, b, match))
    return created


async def test_every_match_gets_exactly_one_dm_conversation(db, factory):
    await _seed(factory, matches=3)
    await _backfill(db)

    matches = (await db.execute(text('SELECT count(*) FROM matches'))).scalar()
    convs = (await db.execute(text("SELECT count(*) FROM conversations WHERE kind = 'dm'"))).scalar()
    orphan_matches = (
        await db.execute(
            text('SELECT count(*) FROM matches m WHERE NOT EXISTS '
                 '(SELECT 1 FROM conversations c WHERE c.match_id = m.id)')
        )
    ).scalar()

    assert convs == matches == 3
    assert orphan_matches == 0


async def test_each_dm_conversation_has_exactly_the_two_match_members(db, factory):
    seeded = await _seed(factory, matches=2)
    await _backfill(db)

    for user_a, user_b, match in seeded:
        rows = (
            await db.execute(
                text('SELECT cm.user_id, cm.role, cm.status FROM conversation_members cm '
                     'JOIN conversations c ON c.id = cm.conversation_id WHERE c.match_id = :m'),
                {'m': match.id},
            )
        ).all()
        assert len(rows) == 2
        assert {r[0] for r in rows} == {user_a.id, user_b.id}
        assert {r[1] for r in rows} == {'member'}
        assert {r[2] for r in rows} == {'active'}


async def test_every_message_is_linked_to_its_matchs_conversation(db, factory):
    await _seed(factory, matches=3, messages_per_match=4)
    await _backfill(db)

    unlinked = (await db.execute(text('SELECT count(*) FROM messages WHERE conversation_id IS NULL'))).scalar()
    mismatched = (
        await db.execute(
            text('SELECT count(*) FROM messages msg JOIN conversations c ON c.id = msg.conversation_id '
                 'WHERE c.match_id IS DISTINCT FROM msg.match_id')
        )
    ).scalar()

    assert unlinked == 0
    assert mismatched == 0  # every message points at its own match's conversation


async def test_per_thread_message_counts_match_the_match_based_view(db, factory):
    seeded = await _seed(factory, matches=3, messages_per_match=5)
    await _backfill(db)

    for _, _, match in seeded:
        by_match = (
            await db.execute(text('SELECT count(*) FROM messages WHERE match_id = :m'), {'m': match.id})
        ).scalar()
        by_conversation = (
            await db.execute(
                text('SELECT count(*) FROM messages msg JOIN conversations c ON c.id = msg.conversation_id '
                     'WHERE c.match_id = :m'),
                {'m': match.id},
            )
        ).scalar()
        assert by_match == by_conversation == 5


async def test_backfill_is_idempotent(db, factory):
    await _seed(factory, matches=2, messages_per_match=3)

    await _backfill(db)
    first = (
        (await db.execute(text('SELECT count(*) FROM conversations'))).scalar(),
        (await db.execute(text('SELECT count(*) FROM conversation_members'))).scalar(),
    )

    await _backfill(db)  # re-running the migration must change nothing
    second = (
        (await db.execute(text('SELECT count(*) FROM conversations'))).scalar(),
        (await db.execute(text('SELECT count(*) FROM conversation_members'))).scalar(),
    )

    assert first == second == (2, 4)


async def test_match_id_is_left_untouched(db, factory):
    """Rollback safety: the old container must still be fully populated after backfill."""
    await _seed(factory, matches=2, messages_per_match=3)
    await _backfill(db)

    null_match_ids = (await db.execute(text('SELECT count(*) FROM messages WHERE match_id IS NULL'))).scalar()
    assert null_match_ids == 0


async def test_read_boundary_backfill_preserves_existing_read_state(db, factory):
    """After the boundary backfill, unread counts match the OLD read_at-based view — already
    read messages don't resurface as unread."""
    from app.features.realtime.service import mark_read

    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msgs = [
        await factory.message(match, a if i % 2 == 0 else b, f'm{i}', created_at=BASE + timedelta(minutes=i))
        for i in range(6)
    ]
    # Simulate pre-migration read state: B read up to msg index 3, and A read nothing.
    # (mark_read stamps read_at AND the boundary; then we clear the boundary to mimic
    # a DB that only had the old read_at.)
    await mark_read(db, reader_id=b.id, match_id=match.id, through_message_id=msgs[3].id)
    await db.execute(text('UPDATE conversation_members SET last_read_message_id = NULL'))
    await db.flush()

    # Old view (read_at): B has 1 unread (a's msg-4), A has 3 unread (all of b's).
    await _backfill_read_boundary(db)

    total_b, _ = await unread_summary(db, b.id)
    total_a, _ = await unread_summary(db, a.id)
    assert total_b == 1  # boundary restored → only the post-read message is unread
    assert total_a == 3
