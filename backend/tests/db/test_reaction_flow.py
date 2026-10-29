"""Reacting end to end (`apply_reaction`): what is broadcast, who is notified, what is taken back.

The reaction report was "it doesn't work like WhatsApp": nobody but the author heard about a
reaction, nothing named the message, a muted chat still pushed, and an un-react left the
notification behind. These pin the behaviour that replaced it.
"""

from __future__ import annotations

import pytest
from sqlalchemy import select, update

from app.features.messages.reaction_flow import apply_reaction
from app.features.messages.reactions import REACTION_ALLOWLIST
from app.features.messages.service import persist_message_idempotent
from app.features.notifications.service import list_notifications
from app.models import Conversation, ConversationMember, Notification
from app.shared.notification_reads import mark_chat_reactions_read

THUMB = REACTION_ALLOWLIST[0]
HEART = REACTION_ALLOWLIST[1]


@pytest.fixture
def frames(monkeypatch, sessions):
    """Capture every user-channel frame, and point the background sessions at the test DB."""
    from app.features.realtime import broadcasts, runtime

    monkeypatch.setattr(runtime, 'AsyncSessionLocal', sessions)
    monkeypatch.setattr(broadcasts, 'AsyncSessionLocal', sessions)
    sent: list[tuple] = []

    async def capture(user_id, frame):
        sent.append((user_id, frame))

    monkeypatch.setattr(runtime.event_bus, 'publish_to_user', capture)
    return sent


@pytest.fixture
def pushes(monkeypatch):
    """Record which notification pushes would be scheduled (the sender is never really enabled
    in tests)."""
    from app.features.realtime import runtime

    scheduled: list[str] = []

    class _Enabled:
        enabled = True

    monkeypatch.setattr(runtime, 'push_sender', _Enabled())
    monkeypatch.setattr(runtime, '_spawn', lambda coro, *, what: (scheduled.append(what), coro.close()))
    return scheduled


async def _dm(db, factory):
    a = await factory.user(display_name='Ama')
    b = await factory.user(display_name='Kofi')
    match = await factory.match(a, b)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()
    message, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body='see you at 5', client_message_id=None,
    )
    return a, b, match, message


def _reaction_frames(sent):
    return [f for _, f in sent if f.get('type') == 'messages.reaction']


async def _notifications(db, user_id):
    return (
        await db.execute(
            select(Notification).where(
                Notification.user_id == user_id, Notification.type == 'message_reaction'
            )
        )
    ).scalars().all()


async def test_every_member_hears_the_resulting_state(db, factory, frames):
    a, b, match, message = await _dm(db, factory)
    state = await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)

    assert [(r.emoji, r.count, r.reacted_by_me) for r in state.reactions] == [(THUMB, 1, True)]
    recipients = {uid for uid, f in frames if f.get('type') == 'messages.reaction'}
    assert recipients == {a.id, b.id}, "the actor's other devices must update too"
    frame = _reaction_frames(frames)[0]
    assert frame['conversation_id'] == str(match.id), 'addressed by the id the inbox matches on'
    assert frame['user_emoji'] == THUMB
    assert frame['reactions'] == [{'emoji': THUMB, 'count': 1}]
    assert frame['actor_name'] == 'Kofi'
    assert frame['message_snippet'] == 'see you at 5'


async def test_a_replace_sends_a_remove_then_an_add_with_one_final_state(db, factory, frames):
    a, b, _, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    frames.clear()
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=HEART, add=True)

    to_a = [f for uid, f in frames if uid == a.id and f.get('type') == 'messages.reaction']
    assert [(f['emoji'], f['added']) for f in to_a] == [(THUMB, False), (HEART, True)]
    assert {f['user_emoji'] for f in to_a} == {HEART}
    assert to_a[-1]['reactions'] == [{'emoji': HEART, 'count': 1}]


async def test_a_repeat_tap_broadcasts_and_notifies_nothing(db, factory, frames):
    a, b, _, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    frames.clear()
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    assert _reaction_frames(frames) == []
    assert len(await _notifications(db, a.id)) == 1


async def test_changing_the_emoji_updates_the_unread_notification_in_place(db, factory, frames, pushes):
    a, b, _, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=HEART, add=True)

    rows = await _notifications(db, a.id)
    assert [(r.detail, r.subject_id) for r in rows] == [(HEART, message.id)]
    assert pushes == ['notification push'], 'one push for one reaction, not one per change'


async def test_reactions_to_two_messages_are_two_notifications(db, factory, frames):
    a, b, match, message = await _dm(db, factory)
    other, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=message.conversation_id,
        body='and bring snacks', client_message_id=None,
    )
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    await apply_reaction(db, message_id=other.id, actor_id=b.id, emoji=HEART, add=True)
    assert len(await _notifications(db, a.id)) == 2


async def test_un_reacting_takes_back_an_unseen_notification(db, factory, frames):
    a, b, _, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    notification_id = (await _notifications(db, a.id))[0].id
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=False)

    assert await _notifications(db, a.id) == []
    retracted = [f for uid, f in frames if uid == a.id and f.get('type') == 'notification.retracted']
    assert retracted == [{'type': 'notification.retracted', 'id': str(notification_id)}]


async def test_a_seen_notification_is_not_taken_back(db, factory, frames):
    a, b, _, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    await db.execute(update(Notification).values(read_at=Notification.created_at))
    await db.commit()
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=False)
    assert len(await _notifications(db, a.id)) == 1


async def test_a_muted_chat_records_the_notification_without_a_push(db, factory, frames, pushes):
    a, b, _, message = await _dm(db, factory)
    await db.execute(
        update(ConversationMember)
        .where(ConversationMember.conversation_id == message.conversation_id, ConversationMember.user_id == a.id)
        .values(muted=True)
    )
    await db.commit()
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)

    assert len(await _notifications(db, a.id)) == 1
    assert pushes == []


async def test_reacting_to_my_own_message_notifies_nobody(db, factory, frames):
    a, b, _, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=a.id, emoji=THUMB, add=True)
    assert await _notifications(db, a.id) == []


async def test_the_listed_notification_quotes_the_message(db, factory, frames):
    a, b, _, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)
    (row,) = await list_notifications(db, a.id)
    assert row.snippet == 'see you at 5'


async def test_opening_the_chat_reads_its_reaction_notifications(db, factory, frames):
    a, b, match, message = await _dm(db, factory)
    await apply_reaction(db, message_id=message.id, actor_id=b.id, emoji=THUMB, add=True)

    cleared = await mark_chat_reactions_read(db, a.id, match.id)
    assert len(cleared) == 1
    assert (await _notifications(db, a.id))[0].read_at is not None
    assert await mark_chat_reactions_read(db, a.id, match.id) == []


def test_the_push_carries_the_chat_so_a_tap_opens_it():
    from app.features.notifications.push import notification_push_data

    data = notification_push_data('message_reaction', {'conversation_id': 'c1', 'target_type': 'dm'})
    assert data == {
        'type': 'notification',
        'notif_type': 'message_reaction',
        'conversation_id': 'c1',
        'target_type': 'dm',
    }
    assert notification_push_data('x', {'type': 'spoofed'})['type'] == 'notification'
