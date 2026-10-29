"""Muting a direct message, and who may see whose "Online" / "Last seen".

Presence is reciprocal and one-to-one only (as in WhatsApp): visible between two people who share
a DM, are not blocked, and both show theirs. Never in groups.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.messages.presence_read import partner_presence
from app.features.messages.router import mute_thread
from app.features.messages.schema import ThreadMuteRequest
from app.features.messages.threads import list_threads_for_user
from app.models import Conversation, ConversationMember, Profile
from app.shared.presence import presence_audience, record_last_seen


@pytest.fixture
def frames(monkeypatch):
    from app.features.realtime import runtime

    sent: list[tuple] = []

    async def capture(user_id, frame):
        sent.append((user_id, frame))

    monkeypatch.setattr(runtime.event_bus, 'publish_to_user', capture)
    return sent


async def _dm(db, factory):
    a = await factory.user(display_name='Ama')
    b = await factory.user(display_name='Kofi')
    match = await factory.match(a, b)
    conversation = (
        await db.execute(select(Conversation).where(Conversation.match_id == match.id))
    ).scalar_one()
    return a, b, match, conversation


async def _hide_presence(db, user):
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    profile.show_presence = False
    await db.commit()


async def test_muting_a_dm_shows_on_the_inbox_and_syncs_my_devices(db, factory, frames):
    a, b, match, conversation = await _dm(db, factory)
    await mute_thread(match.id, ThreadMuteRequest(muted=True), current_user=a, db=db)

    member = (
        await db.execute(
            select(ConversationMember).where(
                ConversationMember.conversation_id == conversation.id, ConversationMember.user_id == a.id
            )
        )
    ).scalar_one()
    assert member.muted is True
    row = next(t for t in await list_threads_for_user(db, a.id) if t.match_id == match.id)
    assert row.muted is True
    assert (a.id, {'type': 'conversation.muted', 'conversation_id': str(match.id), 'muted': True}) in frames
    b_row = next(t for t in await list_threads_for_user(db, b.id) if t.match_id == match.id)
    assert b_row.muted is False, 'mute is per member'


async def test_a_stranger_cannot_mute_someone_elses_chat(db, factory, frames):
    a, b, match, _ = await _dm(db, factory)
    stranger = await factory.user(display_name='S')
    with pytest.raises(HTTPException) as exc:
        await mute_thread(match.id, ThreadMuteRequest(muted=True), current_user=stranger, db=db)
    assert exc.value.status_code == 404


async def test_presence_is_visible_between_dm_partners(db, factory):
    a, b, match, conversation = await _dm(db, factory)
    seen = datetime(2026, 10, 29, 15, 40, tzinfo=UTC)
    await record_last_seen(db, b.id, seen)

    presence = await partner_presence(db, conversation, a.id)
    assert (presence.user_id, presence.visible, presence.online, presence.last_seen_at) == (b.id, True, False, seen)
    assert await presence_audience(db, a.id) == [b.id]


async def test_hiding_presence_is_reciprocal(db, factory):
    a, b, match, conversation = await _dm(db, factory)
    await record_last_seen(db, b.id, datetime.now(UTC))
    await _hide_presence(db, a)

    mine = await partner_presence(db, conversation, a.id)
    assert (mine.visible, mine.last_seen_at) == (False, None), 'hiding yours hides theirs from you'
    theirs = await partner_presence(db, conversation, b.id)
    assert theirs.visible is False
    assert await presence_audience(db, a.id) == []
    assert await presence_audience(db, b.id) == []


async def test_a_block_ends_presence(db, factory):
    a, b, match, conversation = await _dm(db, factory)
    await factory.block(a, b)
    await db.commit()
    assert await presence_audience(db, a.id) == []
    assert await presence_audience(db, b.id) == []


async def test_groups_have_no_presence(db, factory):
    from app.features.groups import service as group_service
    from app.features.groups.schema import GroupCreate

    me = await factory.user(display_name='Me')
    group = await group_service.create_group(
        db, me, GroupCreate(name='Club', category='club', join_policy='open')
    )
    conversation = (
        await db.execute(select(Conversation).where(Conversation.id == group.conversation_id))
    ).scalar_one()
    with pytest.raises(HTTPException) as exc:
        await partner_presence(db, conversation, me.id)
    assert exc.value.status_code == 404
