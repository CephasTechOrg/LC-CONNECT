"""P1/P2 hardening — edge cases beyond the parity net.

- `mark_read` boundary is forward-only (out-of-order reads can't "un-read")
- `mark_delivered` boundary is forward-only and idempotent (report #21's delivered tick)
- `ensure_dm_conversation` is idempotent (never a second conversation / duplicate members)
- new-match provisioning + the DM block rule at the membership layer
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select

from app.features.groups import service as group_service
from app.features.groups.schema import GroupCreate
from app.features.messages.service import (
    delivery_cursor,
    persist_message_idempotent,
    unread_summary,
)
from app.features.realtime.service import mark_delivered, mark_read
from app.models import Conversation, ConversationMember
from app.shared.conversations import blockable_conversation_ids_between, ensure_dm_conversation

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


async def test_blockable_conversation_ids_between_ignores_shared_groups(db, factory):
    a = await factory.user()
    b = await factory.user()
    c = await factory.user()
    match = await factory.match(a, b)
    dm = await ensure_dm_conversation(db, match)
    group = await group_service.create_group(
        db, c, GroupCreate(name='Study Hall', category='club', visibility='public', join_policy='open')
    )
    await group_service.join_group(db, group, a)
    await group_service.join_group(db, group, b)
    await db.commit()

    ids = await blockable_conversation_ids_between(db, a.id, b.id)
    assert dm.id in ids
    assert group.conversation_id not in ids


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


# ── delivery boundary (report #21) ────────────────────────────────────────────
#
# The client re-sends boundaries after every reconnect, and the socket is torn down on every app
# background — so "an acknowledgement arrives twice, or out of order" is the normal case here,
# not an edge case. These pin exactly that.

async def _delivered_id(db, conversation_id, user_id):
    return (
        await db.execute(
            select(ConversationMember.last_delivered_message_id).where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
        )
    ).scalar_one()


async def test_mark_delivered_advances_the_boundary(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msgs = [await factory.message(match, a, f'm{i}', created_at=BASE + timedelta(minutes=i))
            for i in range(3)]
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    assert await _delivered_id(db, conversation_id, b.id) is None, 'nothing acknowledged yet'

    await mark_delivered(db, recipient_id=b.id, match_id=match.id, through_message_id=msgs[2].id)

    assert await _delivered_id(db, conversation_id, b.id) == msgs[2].id


async def test_mark_delivered_boundary_only_moves_forward(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msgs = [await factory.message(match, a, f'm{i}', created_at=BASE + timedelta(minutes=i))
            for i in range(5)]
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    await mark_delivered(db, recipient_id=b.id, match_id=match.id, through_message_id=msgs[3].id)
    # An older acknowledgement arriving late must not "un-deliver" m2 and m3.
    await mark_delivered(db, recipient_id=b.id, match_id=match.id, through_message_id=msgs[1].id)

    assert await _delivered_id(db, conversation_id, b.id) == msgs[3].id


async def test_mark_delivered_is_idempotent(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msg = await factory.message(match, a, 'm', created_at=BASE)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    for _ in range(3):
        await mark_delivered(db, recipient_id=b.id, match_id=match.id, through_message_id=msg.id)

    assert await _delivered_id(db, conversation_id, b.id) == msg.id


async def test_mark_delivered_ignores_a_message_from_another_conversation(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    c = await factory.user(display_name='C')
    match_ab = await factory.match(a, b)
    match_ac = await factory.match(a, c)
    elsewhere = await factory.message(match_ac, a, 'not yours', created_at=BASE)
    conversation_ab = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match_ab.id))
    ).scalar_one()

    # A cross-conversation cursor would otherwise set a boundary to a message the member cannot
    # even see, and the comparison against it on the next advance would be meaningless.
    result = await mark_delivered(
        db, recipient_id=b.id, match_id=match_ab.id, through_message_id=elsewhere.id
    )

    assert result is None
    assert await _delivered_id(db, conversation_ab, b.id) is None


async def test_mark_delivered_ignores_a_non_member(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    outsider = await factory.user(display_name='Outsider')
    match = await factory.match(a, b)
    msg = await factory.message(match, a, 'm', created_at=BASE)

    assert await mark_delivered(
        db, recipient_id=outsider.id, match_id=match.id, through_message_id=msg.id
    ) is None


async def test_delivery_and_read_boundaries_are_independent(db, factory):
    """The two share `_advance_boundary`, so a bug there could cross them — which would either
    mark messages read on delivery (destroying unread counts) or hold the read tick back."""
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msgs = [await factory.message(match, a, f'm{i}', created_at=BASE + timedelta(minutes=i))
            for i in range(3)]
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    # Delivered everything, read only the first — the normal state for an unopened chat.
    await mark_delivered(db, recipient_id=b.id, match_id=match.id, through_message_id=msgs[2].id)
    await mark_read(db, reader_id=b.id, match_id=match.id, through_message_id=msgs[0].id)

    member = (
        await db.execute(
            select(ConversationMember).where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == b.id,
            )
        )
    ).scalar_one()
    assert member.last_delivered_message_id == msgs[2].id
    assert member.last_read_message_id == msgs[0].id

    total, _ = await unread_summary(db, b.id)
    assert total == 2, 'delivery must not mark anything read'


# ── delivery durability (report #21) ──────────────────────────────────────────
#
# The delivered tick used to exist only in the live `messages.delivery` frame: the boundary was
# persisted per member, but nothing returned it. Every page load, app restart and cache miss
# dropped every second tick back to one — which a sender reads as "it never arrived".

async def test_delivery_cursor_is_none_before_anyone_acknowledges(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    await factory.message(match, a, 'm', created_at=BASE)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    assert await delivery_cursor(db, conversation_id, exclude=a.id) is None


async def test_delivery_cursor_reports_the_partner_boundary(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msgs = [await factory.message(match, a, f'm{i}', created_at=BASE + timedelta(minutes=i))
            for i in range(3)]
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    await mark_delivered(db, recipient_id=b.id, match_id=match.id,
                         through_message_id=msgs[1].id)

    cursor = await delivery_cursor(db, conversation_id, exclude=a.id)
    assert cursor == (msgs[1].created_at, msgs[1].id)


async def test_delivery_cursor_excludes_the_asker(db, factory):
    """The sender's own boundary says nothing about whether their message reached anyone. Leaving
    it in would report every message delivered the moment the sender opened the chat."""
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msg = await factory.message(match, a, 'm', created_at=BASE)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    await mark_delivered(db, recipient_id=a.id, match_id=match.id, through_message_id=msg.id)

    assert await delivery_cursor(db, conversation_id, exclude=a.id) is None


async def _group_of(db, factory, n_members):
    """A group with `n_members`, owner first."""
    owner = await factory.user(display_name='Owner')
    group = await group_service.create_group(
        db, owner, GroupCreate(name='CS Club', category='club', visibility='public',
                               join_policy='open')
    )
    members = [owner]
    for i in range(n_members - 1):
        member = await factory.user(display_name=f'M{i}')
        await group_service.join_group(db, group, member)
        members.append(member)
    await db.commit()
    return group, members


async def test_delivery_cursor_requires_every_member(db, factory):
    """"Delivered" is the minimum across members, so one member who has acknowledged nothing
    holds the whole conversation at "nothing" — the correct reading of "everyone has it"."""
    group, members = await _group_of(db, factory, 3)
    sender, quick, silent = members
    message, _ = await persist_message_idempotent(
        db, sender_id=sender.id, match_id=None, conversation_id=group.conversation_id,
        body='hello', client_message_id=None,
    )
    await mark_delivered(db, recipient_id=quick.id, match_id=group.conversation_id,
                         through_message_id=message.id)

    assert await delivery_cursor(db, group.conversation_id, exclude=sender.id) is None

    await mark_delivered(db, recipient_id=silent.id, match_id=group.conversation_id,
                         through_message_id=message.id)
    assert await delivery_cursor(db, group.conversation_id, exclude=sender.id) is not None


async def test_reading_also_advances_delivery(db, factory):
    """A read message was necessarily received. Without this the row could hold "read through m5,
    delivered through m2", which cannot physically happen — and anything reading the delivery
    boundary would take that at face value."""
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msgs = [await factory.message(match, a, f'm{i}', created_at=BASE + timedelta(minutes=i))
            for i in range(3)]
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()

    # Read without any prior delivery acknowledgement — the ordinary case on a busy connection.
    await mark_read(db, reader_id=b.id, match_id=match.id, through_message_id=msgs[2].id)

    assert await _delivered_id(db, conversation_id, b.id) == msgs[2].id
