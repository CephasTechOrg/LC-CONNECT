"""Delete-for-everyone (soft delete). Sender can delete their own message anywhere; a group
admin/owner can delete any message in their group; nobody else can. Deleted messages tombstone
(body suppressed) and never leak the original text."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from app.features.groups import service as group_service
from app.features.groups.schema import GroupCreate
from app.features.messages.service import delete_message, message_read, persist_message_idempotent
from app.shared.conversations import ensure_dm_conversation


async def _group(db, factory, n=2):
    owner = await factory.user(display_name='Owner')
    group = await group_service.create_group(db, owner, GroupCreate(name='Group', category='club', join_policy='open'))
    members = [owner]
    for _ in range(n - 1):
        u = await factory.user()
        await group_service.join_group(db, group, u)
        members.append(u)
    await db.commit()
    return group, members


async def _group_msg(db, group, sender, body='hi'):
    msg, _ = await persist_message_idempotent(
        db, sender_id=sender.id, match_id=None, conversation_id=group.conversation_id, body=body, client_message_id=None
    )
    await db.commit()
    return msg


async def test_sender_can_delete_own_and_it_tombstones(db, factory):
    group, members = await _group(db, factory, 2)
    member = members[1]
    msg = await _group_msg(db, group, member, body='secret')

    deleted = await delete_message(db, msg.id, member.id)
    assert deleted.deleted_at is not None
    dto = message_read(deleted)
    assert dto.deleted is True
    assert dto.body == ''  # original text never leaves the server


async def test_group_admin_can_delete_another_members_message(db, factory):
    group, members = await _group(db, factory, 2)
    owner, member = members
    msg = await _group_msg(db, group, member)  # the member's message
    deleted = await delete_message(db, msg.id, owner.id)  # owner (admin tier) removes it
    assert deleted.deleted_at is not None


async def test_plain_member_cannot_delete_someone_elses_message(db, factory):
    group, members = await _group(db, factory, 3)
    _owner, m1, m2 = members
    msg = await _group_msg(db, group, m1)
    with pytest.raises(HTTPException) as exc:
        await delete_message(db, msg.id, m2.id)  # m2 is a plain member, not the sender
    assert exc.value.status_code == 403


async def test_non_member_cannot_delete(db, factory):
    group, members = await _group(db, factory, 2)
    outsider = await factory.user()
    msg = await _group_msg(db, group, members[0])
    with pytest.raises(HTTPException) as exc:
        await delete_message(db, msg.id, outsider.id)
    assert exc.value.status_code == 404


async def test_dm_partner_cannot_delete_but_sender_can(db, factory):
    a = await factory.user()
    b = await factory.user()
    match = await factory.match(a, b)
    conv = await ensure_dm_conversation(db, match)
    await db.commit()
    msg, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conv.id, body='hey', client_message_id=None
    )
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await delete_message(db, msg.id, b.id)  # DM has no admins — partner can't delete
    assert exc.value.status_code == 403

    deleted = await delete_message(db, msg.id, a.id)  # the sender can
    assert deleted.deleted_at is not None


async def test_delete_is_idempotent(db, factory):
    group, members = await _group(db, factory, 2)
    msg = await _group_msg(db, group, members[1])
    first = await delete_message(db, msg.id, members[1].id)
    stamp = first.deleted_at
    second = await delete_message(db, msg.id, members[1].id)  # deleting again is a no-op
    assert second.deleted_at == stamp
