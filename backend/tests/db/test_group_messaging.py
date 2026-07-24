"""P4 — group messaging over the shared conversation layer.

Verifies that group conversations flow through the same send/authorize/unread path as DMs:
group members can send + receive, non-members are rejected, the read boundary works for N
members, and removal revokes membership.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from app.features.groups import service as group_service
from app.features.groups.schema import GroupCreate
from app.features.messages.service import page_thread, persist_message_idempotent, unread_summary
from app.features.realtime.service import WsForbidden, authorize_conversation, mark_read
from app.models import Message
from app.shared.conversations import active_member_ids, active_members_with_mute

BASE = datetime(2026, 1, 1, 12, 0, 0, tzinfo=UTC)


async def _group_with_members(db, factory, n_members=3):
    owner = await factory.user(display_name='Owner')
    group = await group_service.create_group(
        db, owner, GroupCreate(name='CS Club', category='club', visibility='public', join_policy='open')
    )
    members = [owner]
    for i in range(n_members - 1):
        u = await factory.user(display_name=f'M{i}')
        await group_service.join_group(db, group, u)
        members.append(u)
    await db.commit()
    return group, members


async def test_group_member_can_send_and_it_is_addressed_by_conversation_id(db, factory):
    group, members = await _group_with_members(db, factory, n_members=3)
    sender = members[1]

    # Group chat is addressed by the conversation id directly (not a match).
    conversation = await authorize_conversation(db, sender.id, group.conversation_id)
    assert conversation.id == group.conversation_id and conversation.kind == 'group'

    msg, created = await persist_message_idempotent(
        db, sender_id=sender.id, match_id=None, conversation_id=group.conversation_id,
        body='hello group', client_message_id=None,
    )
    await db.commit()
    assert created

    page = await page_thread(db, group.conversation_id, before_created_at=None, before_id=None, limit=10)
    assert [m.body for m in page] == ['hello group']

    # Serialize like the REST endpoint does — this is where the 500 (null match_id) happened.
    from app.features.messages.service import message_read
    dto = message_read(page[0])
    assert dto.match_id is None                              # group message → no match
    assert dto.conversation_id == group.conversation_id     # addressed by the conversation


async def test_non_member_cannot_access_group_conversation(db, factory):
    group, _ = await _group_with_members(db, factory, n_members=2)
    outsider = await factory.user()
    with pytest.raises(WsForbidden):
        await authorize_conversation(db, outsider.id, group.conversation_id)


async def test_send_fans_out_to_all_other_members(db, factory):
    group, members = await _group_with_members(db, factory, n_members=4)
    sender = members[0]

    recipients = await active_member_ids(db, group.conversation_id, exclude=sender.id)
    assert set(recipients) == {m.id for m in members[1:]}  # everyone except the sender


async def test_muted_members_are_flagged_for_push_exclusion(db, factory):
    group, members = await _group_with_members(db, factory, n_members=3)
    # Mute one member.
    muted_member = await group_service.membership(db, group.conversation_id, members[2].id)
    muted_member.muted = True
    await db.commit()

    rows = dict(await active_members_with_mute(db, group.conversation_id, exclude=members[0].id))
    assert rows[members[1].id] is False
    assert rows[members[2].id] is True  # push will skip this one


async def test_group_unread_uses_the_per_member_boundary(db, factory):
    group, members = await _group_with_members(db, factory, n_members=3)
    owner, reader = members[0], members[1]

    # Owner sends 3 messages.
    msgs = []
    for i in range(3):
        m = Message(
            conversation_id=group.conversation_id, sender_id=owner.id, body=f'g{i}',
            created_at=BASE + timedelta(minutes=i),
        )
        db.add(m)
        await db.flush()
        msgs.append(m)
    await db.commit()

    total_before, per = await unread_summary(db, reader.id)
    assert per.get(group.conversation_id) == 3  # all three are unread for the reader

    await mark_read(db, reader_id=reader.id, match_id=group.conversation_id, through_message_id=msgs[1].id)
    total_after, per_after = await unread_summary(db, reader.id)
    assert per_after.get(group.conversation_id) == 1  # only g2 remains


async def test_rest_access_resolves_group_by_conversation_id(db, factory):
    """The REST message endpoints (via `accessible_conversation`) accept a group conversation
    id for members and 404 for outsiders — the same helper still resolves DM match ids."""
    from fastapi import HTTPException

    from app.shared.conversations import accessible_conversation

    group, members = await _group_with_members(db, factory, n_members=2)
    member, owner = members[1], members[0]

    conv = await accessible_conversation(db, group.conversation_id, member.id)
    assert conv.id == group.conversation_id and conv.kind == 'group'

    outsider = await factory.user()
    with pytest.raises(HTTPException) as exc:
        await accessible_conversation(db, group.conversation_id, outsider.id)
    assert exc.value.status_code == 404

    # DM parity: a match id still resolves to its DM conversation for a member.
    dm_match = await factory.match(owner, member)
    dm_conv = await accessible_conversation(db, dm_match.id, owner.id)
    assert dm_conv.kind == 'dm'


async def test_removed_member_loses_access(db, factory):
    group, members = await _group_with_members(db, factory, n_members=3)
    owner_member = await group_service.membership(db, group.conversation_id, members[0].id)
    target = members[2]

    await group_service.remove_member(db, group, owner_member, target.id, ban=False)
    await db.commit()

    with pytest.raises(WsForbidden):
        await authorize_conversation(db, target.id, group.conversation_id)
