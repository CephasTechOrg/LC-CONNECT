"""Group integration tests: create, join flows, capacity (incl. a real race), visibility."""

from __future__ import annotations

import asyncio

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.groups import service
from app.features.groups.schema import GroupCreate
from app.models import Conversation, ConversationMember, Group, User


async def _make_group(db, owner, **overrides) -> Group:
    payload = GroupCreate(
        name=overrides.pop('name', 'CS Club'),
        category=overrides.pop('category', 'club'),
        visibility=overrides.pop('visibility', 'public'),
        join_policy=overrides.pop('join_policy', 'open'),
        max_members=overrides.pop('max_members', None),
        description=overrides.pop('description', None),
    )
    group = await service.create_group(db, owner, payload)
    await db.commit()
    return group


# ── create ─────────────────────────────────────────────────────────────────────

async def test_create_group_makes_conversation_and_owner_member(db, factory):
    owner = await factory.user(display_name='Owner')
    group = await _make_group(db, owner)

    conversation = await db.get(Conversation, group.conversation_id)
    assert conversation.kind == 'group'

    owner_member = await service.membership(db, group.conversation_id, owner.id)
    assert owner_member.role == 'owner' and owner_member.status == 'active'
    assert await service.active_member_count(db, group.conversation_id) == 1


# ── join flows ───────────────────────────────────────────────────────────────────

async def test_open_group_joins_instantly(db, factory):
    owner = await factory.user()
    joiner = await factory.user()
    group = await _make_group(db, owner, join_policy='open')

    result = await service.join_group(db, group, joiner)
    await db.commit()
    assert result.status == 'active'
    assert await service.active_member_count(db, group.conversation_id) == 2


async def test_approval_group_requires_admin_approval(db, factory):
    owner = await factory.user()
    joiner = await factory.user()
    group = await _make_group(db, owner, join_policy='approval')

    result = await service.join_group(db, group, joiner)
    await db.commit()
    assert result.status == 'requested'
    assert await service.active_member_count(db, group.conversation_id) == 1  # not yet active

    await service.approve_request(db, group, joiner.id)
    await db.commit()
    assert await service.active_member_count(db, group.conversation_id) == 2


async def test_rejecting_a_request_leaves_them_out(db, factory):
    owner = await factory.user()
    joiner = await factory.user()
    group = await _make_group(db, owner, join_policy='approval')
    await service.join_group(db, group, joiner)
    await db.commit()

    await service.reject_request(db, group, joiner.id)
    await db.commit()
    member = await service.membership(db, group.conversation_id, joiner.id)
    assert member.status == 'removed'
    assert await service.active_member_count(db, group.conversation_id) == 1


async def test_invite_only_group_rejects_open_join_but_accepts_invite(db, factory):
    owner = await factory.user()
    invitee = await factory.user()
    await factory.match(owner, invitee)  # you can only invite a connection
    group = await _make_group(db, owner, join_policy='invite')

    with pytest.raises(HTTPException) as exc:
        await service.join_group(db, group, invitee)
    assert exc.value.status_code == 403

    await service.invite_user(db, group, invitee.id, invited_by=owner.id)
    await db.commit()
    result = await service.accept_invite(db, group, invitee)
    await db.commit()
    assert result.status == 'active'
    assert await service.active_member_count(db, group.conversation_id) == 2


async def test_invite_requires_a_connection(db, factory):
    """You can only invite people you're connected with. A stranger (no shared match) is
    rejected with 403; once connected, the same invite succeeds."""
    owner = await factory.user()
    stranger = await factory.user()
    group = await _make_group(db, owner, join_policy='invite')

    with pytest.raises(HTTPException) as exc:
        await service.invite_user(db, group, stranger.id, invited_by=owner.id)
    assert exc.value.status_code == 403
    assert await service.membership(db, group.conversation_id, stranger.id) is None

    await factory.match(owner, stranger)  # now they're connected
    await service.invite_user(db, group, stranger.id, invited_by=owner.id)
    await db.commit()
    member = await service.membership(db, group.conversation_id, stranger.id)
    assert member.status == 'invited'


async def test_banned_user_cannot_join(db, factory):
    owner = await factory.user()
    outcast = await factory.user()
    group = await _make_group(db, owner, join_policy='open')
    db.add(
        ConversationMember(conversation_id=group.conversation_id, user_id=outcast.id, role='member', status='banned')
    )
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await service.join_group(db, group, outcast)
    assert exc.value.status_code == 403


# ── capacity ─────────────────────────────────────────────────────────────────────

async def test_full_group_rejects_further_joins(db, factory):
    owner = await factory.user()
    group = await _make_group(db, owner, join_policy='open', max_members=2)  # owner + 1

    first = await factory.user()
    await service.join_group(db, group, first)
    await db.commit()

    second = await factory.user()
    with pytest.raises(HTTPException) as exc:
        await service.join_group(db, group, second)
    assert exc.value.status_code == 409


async def test_capacity_is_race_safe_under_concurrent_joins(db, sessions, factory):
    """Two users join a 1-slot group at the same time on separate transactions — the
    FOR UPDATE row lock must let exactly one in."""
    owner = await factory.user()
    group = await _make_group(db, owner, join_policy='open', max_members=2)  # owner + exactly 1 slot
    u1 = await factory.user()
    u2 = await factory.user()
    await db.commit()
    group_id, u1_id, u2_id = group.id, u1.id, u2.id

    async def join_on_own_session(user_id):
        async with sessions() as s:
            g = await s.get(Group, group_id)
            u = await s.get(User, user_id)
            try:
                await service.join_group(s, g, u)
                await s.commit()
                return 'ok'
            except HTTPException as exc:
                await s.rollback()
                return exc.status_code

    results = await asyncio.gather(join_on_own_session(u1_id), join_on_own_session(u2_id))

    assert sorted(str(r) for r in results) == ['409', 'ok']  # exactly one winner
    final = (
        await db.execute(
            select(func.count()).select_from(ConversationMember).where(
                ConversationMember.conversation_id == group.conversation_id,
                ConversationMember.status == 'active',
            )
        )
    ).scalar()
    assert final == 2  # owner + one joiner, never 3


# ── visibility ───────────────────────────────────────────────────────────────────

async def test_private_group_is_hidden_from_non_members(db, factory):
    owner = await factory.user()
    outsider = await factory.user()
    group = await _make_group(db, owner, visibility='private')

    outsider_member = await service.membership(db, group.conversation_id, outsider.id)
    with pytest.raises(HTTPException) as exc:
        service.assert_group_visible(group, outsider_member)
    assert exc.value.status_code == 404

    owner_member = await service.membership(db, group.conversation_id, owner.id)
    service.assert_group_visible(group, owner_member)  # owner sees it


async def test_discovery_lists_only_public_groups(db, factory):
    owner = await factory.user()
    await _make_group(db, owner, name='Public Club', visibility='public')
    await _make_group(db, owner, name='Unlisted House', visibility='unlisted')
    await _make_group(db, owner, name='Secret Society', visibility='private')

    found = await service.discover_groups(db, query=None, category=None, limit=50)
    names = {g.name for g in found}
    assert names == {'Public Club'}  # unlisted + private never listed


# ── leave ────────────────────────────────────────────────────────────────────────

async def test_owner_must_transfer_before_leaving(db, factory):
    owner = await factory.user()
    group = await _make_group(db, owner)
    owner_member = await service.membership(db, group.conversation_id, owner.id)

    with pytest.raises(HTTPException) as exc:
        await service.leave_group(db, group, owner_member)
    assert exc.value.status_code == 409


async def test_member_can_leave(db, factory):
    owner = await factory.user()
    member_user = await factory.user()
    group = await _make_group(db, owner, join_policy='open')
    await service.join_group(db, group, member_user)
    await db.commit()

    member = await service.membership(db, group.conversation_id, member_user.id)
    await service.leave_group(db, group, member)
    await db.commit()
    assert member.status == 'removed'
    assert await service.active_member_count(db, group.conversation_id) == 1
