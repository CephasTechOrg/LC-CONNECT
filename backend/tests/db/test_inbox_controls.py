"""Pin and archive a chat, search message text, and see which connections are online."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.messages.inbox_state import set_thread_state
from app.features.messages.presence_read import presence_for_users
from app.features.messages.schema import ThreadStateRequest
from app.features.messages.search import excerpt, search_messages
from app.features.messages.threads import list_threads_for_user
from app.models import Block, Conversation, Match, Profile
from app.shared.presence import presence_audience


async def _chat(db, factory, me, name='Kofi'):
    other = await factory.user(display_name=name)
    match = await factory.match(me, other)
    conversation = (await db.execute(select(Conversation).where(Conversation.match_id == match.id))).scalar_one()
    return other, match, conversation


async def test_pins_are_capped_at_three(db, factory):
    me = await factory.user()
    chats = [(await _chat(db, factory, me, name=f'P{i}'))[2] for i in range(4)]
    for conversation in chats[:3]:
        await set_thread_state(db, conversation, me.id, ThreadStateRequest(pinned=True))
    with pytest.raises(HTTPException) as exc:
        await set_thread_state(db, chats[3], me.id, ThreadStateRequest(pinned=True))
    assert exc.value.status_code == 409


async def test_two_devices_pinning_at_once_cannot_pass_the_cap(db, sessions, factory):
    me = await factory.user()
    chats = [(await _chat(db, factory, me, name=f'P{i}'))[2] for i in range(4)]
    for conversation in chats[:2]:
        await set_thread_state(db, conversation, me.id, ThreadStateRequest(pinned=True))
    await db.commit()

    async def pin(conversation):
        async with sessions() as session:
            fresh = await session.get(Conversation, conversation.id)
            try:
                await set_thread_state(session, fresh, me.id, ThreadStateRequest(pinned=True))
                return True
            except HTTPException:
                return False

    results = await asyncio.gather(pin(chats[2]), pin(chats[3]))
    assert sorted(results) == [False, True]


async def test_archiving_unpins_and_shows_on_the_inbox(db, factory):
    me = await factory.user()
    _, _, conversation = await _chat(db, factory, me)
    await set_thread_state(db, conversation, me.id, ThreadStateRequest(pinned=True))
    state = await set_thread_state(db, conversation, me.id, ThreadStateRequest(archived=True))
    assert state.archived and state.pinned_at is None

    row = (await list_threads_for_user(db, me.id))[0]
    assert row.archived is True and row.pinned_at is None


async def test_search_finds_my_messages_only_and_skips_deleted_and_blocked(db, factory):
    me = await factory.user()
    kofi, kofi_match, _ = await _chat(db, factory, me, name='Kofi')
    ama, ama_match, _ = await _chat(db, factory, me, name='Ama')
    stranger_a, stranger_b = await factory.user(), await factory.user()
    stranger_match = await factory.match(stranger_a, stranger_b)

    now = datetime.now(UTC)
    found = await factory.message(kofi_match, kofi, 'Library at 6 for the chemistry review?', created_at=now)
    gone = await factory.message(kofi_match, me, 'chemistry notes attached', created_at=now - timedelta(minutes=1))
    gone.deleted_at = now
    await factory.message(ama_match, ama, 'chemistry is hard', created_at=now - timedelta(minutes=2))
    await factory.message(stranger_match, stranger_a, 'chemistry secret', created_at=now)
    db.add(Block(blocker_id=me.id, blocked_id=ama.id))
    await db.commit()

    hits = await search_messages(db, me.id, 'CHEMISTRY', limit=20)
    assert [h.message_id for h in hits] == [found.id]
    assert hits[0].title == 'Kofi' and hits[0].thread_id == kofi_match.id


def test_the_excerpt_keeps_the_match_in_view():
    body = 'word ' * 60 + 'needle in the middle ' + 'word ' * 60
    text = excerpt(body, 'needle')
    assert 'needle' in text and text.startswith('…') and text.endswith('…')


async def test_connections_see_each_other_online_without_ever_messaging(db, factory):
    me, friend = await factory.user(), await factory.user()
    db.add(Match(user_a_id=min(me.id, friend.id), user_b_id=max(me.id, friend.id)))
    await db.commit()

    assert friend.id in await presence_audience(db, me.id)
    [row] = await presence_for_users(db, me.id, [friend.id])
    assert row.visible is True


async def test_disconnecting_or_hiding_ends_presence_both_ways(db, factory):
    me = await factory.user()
    friend, match, _ = await _chat(db, factory, me)
    stranger = await factory.user()

    [row] = await presence_for_users(db, me.id, [stranger.id])
    assert row.visible is False, 'only connections and staff partners'

    profile = (await db.execute(select(Profile).where(Profile.user_id == me.id))).scalar_one()
    profile.show_presence = False
    await db.commit()
    assert (await presence_for_users(db, me.id, [friend.id]))[0].visible is False
    profile.show_presence = True
    match.disconnected_at = datetime.now(UTC)
    await db.commit()
    assert friend.id not in await presence_audience(db, me.id)
