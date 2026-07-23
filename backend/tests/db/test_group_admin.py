"""P5 — group admin surface: edit, role changes, ownership transfer, delete, report targets."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.groups import service as gs
from app.features.groups.schema import GroupCreate, GroupUpdate
from app.features.safety.schema import ReportCreate
from app.features.safety.service import create_report
from app.models import Conversation, ConversationMember, Group, Message


async def _group(db, factory, **kw):
    owner = await factory.user(display_name='Owner')
    group = await gs.create_group(db, owner, GroupCreate(name='Club', category='club', join_policy='open', **kw))
    await db.commit()
    return owner, group


async def _join(db, group, factory):
    u = await factory.user()
    await gs.join_group(db, group, u)
    await db.commit()
    return u


# ── edit ──────────────────────────────────────────────────────────────────────

async def test_update_group_changes_fields(db, factory):
    _, group = await _group(db, factory)
    await gs.update_group(db, group, GroupUpdate(name='Renamed', visibility='unlisted').model_dump(exclude_unset=True))
    await db.commit()
    assert group.name == 'Renamed'
    assert group.visibility == 'unlisted'


# ── roles + ownership ───────────────────────────────────────────────────────────

async def test_admin_can_promote_a_member(db, factory):
    owner, group = await _group(db, factory)
    member = await _join(db, group, factory)
    owner_m = await gs.membership(db, group.conversation_id, owner.id)

    await gs.change_role(db, group, owner_m, member.id, 'admin')
    await db.commit()
    assert (await gs.membership(db, group.conversation_id, member.id)).role == 'admin'


async def test_transfer_ownership_keeps_exactly_one_owner(db, factory):
    owner, group = await _group(db, factory)
    heir = await _join(db, group, factory)
    owner_m = await gs.membership(db, group.conversation_id, owner.id)

    await gs.transfer_ownership(db, group, owner_m, heir.id)
    await db.commit()

    assert group.owner_id == heir.id
    assert (await gs.membership(db, group.conversation_id, heir.id)).role == 'owner'
    assert (await gs.membership(db, group.conversation_id, owner.id)).role == 'admin'  # steps down
    owners = (
        await db.execute(
            select(func.count()).select_from(ConversationMember).where(
                ConversationMember.conversation_id == group.conversation_id,
                ConversationMember.role == 'owner',
            )
        )
    ).scalar()
    assert owners == 1  # never zero, never two


async def test_admin_cannot_moderate_another_admin(db, factory):
    owner, group = await _group(db, factory)
    a1 = await _join(db, group, factory)
    a2 = await _join(db, group, factory)
    owner_m = await gs.membership(db, group.conversation_id, owner.id)
    await gs.change_role(db, group, owner_m, a1.id, 'admin')
    await gs.change_role(db, group, owner_m, a2.id, 'admin')
    await db.commit()

    a1_m = await gs.membership(db, group.conversation_id, a1.id)
    with pytest.raises(HTTPException) as exc:
        await gs.change_role(db, group, a1_m, a2.id, 'member')  # admin vs admin → forbidden
    assert exc.value.status_code == 403


# ── delete ────────────────────────────────────────────────────────────────────

async def test_delete_group_cascades_to_conversation_members_and_messages(db, factory):
    owner, group = await _group(db, factory)
    member = await _join(db, group, factory)
    db.add(Message(conversation_id=group.conversation_id, sender_id=member.id, body='hi'))
    await db.commit()
    conv_id = group.conversation_id

    group_id = group.id
    conversation = await db.get(Conversation, conv_id)
    await db.delete(conversation)  # what the delete route does
    await db.commit()
    db.expire_all()  # drop the identity-map cache so gets reflect the DB cascade

    # Fresh count queries hit the DB (not the session cache).
    async def count(model, col, value):
        return (await db.execute(select(func.count()).select_from(model).where(col == value))).scalar()

    assert await count(Group, Group.id, group_id) == 0  # cascaded from the conversation
    assert await count(ConversationMember, ConversationMember.conversation_id, conv_id) == 0
    assert await count(Message, Message.conversation_id, conv_id) == 0


# ── report targets ──────────────────────────────────────────────────────────────

async def test_can_report_a_group(db, factory):
    reporter = await factory.user()
    _, group = await _group(db, factory)
    report = await create_report(db, reporter.id, ReportCreate(group_id=group.id, reason='spam group'))
    assert report.group_id == group.id


async def test_can_report_a_message(db, factory):
    reporter = await factory.user()
    owner, group = await _group(db, factory)
    msg = Message(conversation_id=group.conversation_id, sender_id=owner.id, body='bad')
    db.add(msg)
    await db.commit()
    report = await create_report(db, reporter.id, ReportCreate(message_id=msg.id, reason='abuse'))
    assert report.message_id == msg.id


def test_report_requires_a_target():
    with pytest.raises(ValueError, match='report target'):
        ReportCreate(reason='no target')
