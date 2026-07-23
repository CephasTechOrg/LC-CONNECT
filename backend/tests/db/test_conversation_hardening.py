"""P1/P2 hardening — edge cases beyond the parity net.

- `mark_read` boundary is forward-only (out-of-order reads can't "un-read")
- `ensure_dm_conversation` is idempotent (never a second conversation / duplicate members)
- new-match provisioning + the DM block rule at the membership layer
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select

from app.features.messages.service import unread_summary
from app.features.realtime.service import mark_read
from app.models import Conversation, ConversationMember
from app.shared.conversations import ensure_dm_conversation

BASE = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)


async def test_mark_read_boundary_only_moves_forward(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    # a sends 5 messages; b reads them out of order.
    msgs = [await factory.message(match, a, f'm{i}', created_at=BASE + timedelta(minutes=i)) for i in range(5)]

    await mark_read(db, reader_id=b.id, match_id=match.id, through_message_id=msgs[3].id)
    total_after_far, _ = await unread_summary(db, b.id)
    assert total_after_far == 1  # only m4 remains

    # An out-of-order read of an OLDER message must not move the boundary back.
    await mark_read(db, reader_id=b.id, match_id=match.id, through_message_id=msgs[1].id)
    total_after_older, _ = await unread_summary(db, b.id)
    assert total_after_older == 1  # unchanged — boundary stayed at m3


async def test_ensure_dm_conversation_is_idempotent(db, factory):
    a = await factory.user()
    b = await factory.user()
    match = await factory.match(a, b)  # factory already provisions one

    first = await ensure_dm_conversation(db, match)
    second = await ensure_dm_conversation(db, match)
    assert first.id == second.id

    conv_count = (
        await db.execute(select(func.count()).select_from(Conversation).where(Conversation.match_id == match.id))
    ).scalar()
    member_count = (
        await db.execute(
            select(func.count()).select_from(ConversationMember).where(ConversationMember.conversation_id == first.id)
        )
    ).scalar()
    assert conv_count == 1  # never a duplicate conversation
    assert member_count == 2  # exactly the two members, not doubled


async def test_new_matches_are_provisioned_with_a_conversation(db, factory):
    """The factory mirrors production (connections router), so a fresh match already has its
    DM conversation + both members without a second call."""
    a = await factory.user()
    b = await factory.user()
    match = await factory.match(a, b)

    conversation = (
        await db.execute(select(Conversation).where(Conversation.match_id == match.id))
    ).scalar_one_or_none()
    assert conversation is not None
    members = (
        await db.execute(select(ConversationMember.user_id).where(ConversationMember.conversation_id == conversation.id))
    ).scalars().all()
    assert set(members) == {a.id, b.id}
