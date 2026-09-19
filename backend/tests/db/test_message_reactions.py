"""Message reactions — report #4 (checklist 3.6).

The interesting properties are concurrency and authorization, not "a row gets written":

* a toggle must be **idempotent** in both directions, because a double-tap and a retry after a
  dropped response are indistinguishable from the client's side;
* the aggregate must be **one query per page**, never one per message;
* a message id alone must reveal nothing to someone outside the conversation.
"""

from __future__ import annotations

import asyncio

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.messages.reactions import (
    REACTION_ALLOWLIST,
    reactions_for,
    toggle_reaction,
)
from app.features.messages.service import delete_message, persist_message_idempotent
from app.models import Conversation, MessageReaction

THUMB = REACTION_ALLOWLIST[0]
HEART = REACTION_ALLOWLIST[1]


async def _dm(db, factory):
    """Two matched users and a message from the first."""
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()
    message, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body='hello', client_message_id=None,
    )
    return a, b, message


# ── the toggle ────────────────────────────────────────────────────────────────

async def test_reacting_twice_is_idempotent(db, factory):
    """A double-tap must not create two rows, and must not surface an error — reporting a conflict
    would make the client undo an optimistic chip that is in fact correct."""
    a, b, message = await _dm(db, factory)

    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    rows = (await db.execute(select(MessageReaction))).scalars().all()
    assert len(rows) == 1


async def test_concurrent_reactions_leave_one_row(db, factory, sessions):
    """Two devices on the same account, or one very fast thumb. The unique constraint is the
    arbiter and the loser treats its IntegrityError as success."""
    a, b, message = await _dm(db, factory)

    async def react():
        async with sessions() as session:
            await toggle_reaction(
                session, message_id=message.id, user_id=b.id, emoji=THUMB, add=True
            )

    results = await asyncio.gather(react(), react(), return_exceptions=True)

    assert [r for r in results if isinstance(r, Exception)] == []
    rows = (await db.execute(select(MessageReaction))).scalars().all()
    assert len(rows) == 1


async def test_removing_is_idempotent(db, factory):
    a, b, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=False)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=False)

    assert (await db.execute(select(MessageReaction))).scalars().all() == []


async def test_removing_one_emoji_leaves_the_others(db, factory):
    a, b, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=HEART, add=True)

    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=False)

    remaining = (await db.execute(select(MessageReaction.emoji))).scalars().all()
    assert remaining == [HEART]


async def test_two_people_can_send_the_same_emoji(db, factory):
    """The constraint is (message, user, emoji) — per person, not per message. Getting this wrong
    would mean the second reactor silently replaced the first."""
    a, b, message = await _dm(db, factory)

    await toggle_reaction(db, message_id=message.id, user_id=a.id, emoji=THUMB, add=True)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    rows = (await db.execute(select(MessageReaction))).scalars().all()
    assert len(rows) == 2


# ── the allowlist ─────────────────────────────────────────────────────────────

async def test_an_emoji_outside_the_allowlist_is_refused(db, factory):
    """Free text would be an abuse surface — the value renders straight into the UI — and would
    make the per-message aggregate unbounded."""
    a, b, message = await _dm(db, factory)

    with pytest.raises(HTTPException) as exc:
        await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji='🦑', add=True)
    assert exc.value.status_code == 422

    assert (await db.execute(select(MessageReaction))).scalars().all() == []


async def test_the_allowlist_is_bounded(db):
    # The design caps this at 8: it bounds the aggregate and the chip strip's width.
    assert 1 <= len(REACTION_ALLOWLIST) <= 8
    assert len(set(REACTION_ALLOWLIST)) == len(REACTION_ALLOWLIST)


# ── authorization and deleted messages ───────────────────────────────────────

async def test_a_non_member_cannot_react(db, factory):
    """Without the membership gate, anyone holding a message id could react to a private
    conversation — and find out it exists."""
    a, b, message = await _dm(db, factory)
    outsider = await factory.user(display_name='Outsider')

    with pytest.raises(HTTPException) as exc:
        await toggle_reaction(db, message_id=message.id, user_id=outsider.id, emoji=THUMB, add=True)
    assert exc.value.status_code == 404


async def test_reacting_to_an_unknown_message_is_404(db, factory):
    from uuid import uuid4

    a = await factory.user(display_name='A')
    with pytest.raises(HTTPException) as exc:
        await toggle_reaction(db, message_id=uuid4(), user_id=a.id, emoji=THUMB, add=True)
    assert exc.value.status_code == 404


async def test_reacting_to_a_deleted_message_is_refused(db, factory):
    """The body of a deleted message is never sent to clients, so a reaction on one would hang off
    a tombstone nobody can read."""
    a, b, message = await _dm(db, factory)
    await delete_message(db, message.id, a.id)

    with pytest.raises(HTTPException) as exc:
        await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)
    assert exc.value.status_code == 409


# ── the aggregate ─────────────────────────────────────────────────────────────

async def test_aggregate_counts_and_flags_the_viewer(db, factory):
    a, b, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=a.id, emoji=THUMB, add=True)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    for_a = await reactions_for(db, [message.id], viewer_id=a.id)
    summary = for_a[message.id][0]
    assert summary.emoji == THUMB
    assert summary.count == 2
    # Answered in the same grouped query — no second request to learn whether to fill the chip.
    assert summary.reacted_by_me is True

    outsider = await factory.user(display_name='Outsider')
    for_outsider = await reactions_for(db, [message.id], viewer_id=outsider.id)
    assert for_outsider[message.id][0].reacted_by_me is False


async def test_aggregate_is_one_query_for_a_whole_page(db, factory):
    """The property that matters at 50 messages a page. A per-message query was ~3 seconds before
    the API and database were co-located, and is still fifty round trips after.
    """
    a, b, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    from uuid import uuid4

    # A page of ids, only one of which has reactions.
    page = [message.id] + [uuid4() for _ in range(49)]
    result = await reactions_for(db, page, viewer_id=a.id)

    assert list(result) == [message.id], 'messages without reactions cost nothing to report'


async def test_aggregate_of_an_empty_page_touches_the_database_not_at_all(db):
    assert await reactions_for(db, [], viewer_id=None) == {}


async def test_aggregate_order_follows_the_picker(db, factory):
    """A chip strip that reshuffles between requests looks broken, so the order is the allowlist's
    rather than whatever the database returns."""
    a, b, message = await _dm(db, factory)
    # Added in reverse picker order.
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=HEART, add=True)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    summaries = (await reactions_for(db, [message.id], viewer_id=a.id))[message.id]
    assert [s.emoji for s in summaries] == [THUMB, HEART]
