"""A reaction has to reach someone who is not looking at the conversation.

Reactions fan out on the **conversation** channel, which reaches only clients with that chat open.
That was the whole visibility of the feature: with the app in your pocket, or simply on another
screen, someone reacting to your message produced no inbox change, no badge and no push — you
found out only if you later reopened the thread and happened to scroll to that message.

These pin the notification that closes the gap, and the three cases where it must stay quiet.
"""

from __future__ import annotations

import pytest
from sqlalchemy import select

from app.features.messages.reactions import REACTION_ALLOWLIST, toggle_reaction
from app.features.messages.service import persist_message_idempotent
from app.features.notifications.service import unread_duplicate_exists
from app.features.realtime.runtime import PUSHABLE_NOTIFICATION_TYPES, emit_notification
from app.models import Conversation, Notification

THUMB = REACTION_ALLOWLIST[0]
HEART = REACTION_ALLOWLIST[1]


async def _dm(db, factory):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()
    message, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body='see you at 5', client_message_id=None,
    )
    return a, b, message


@pytest.fixture(autouse=True)
def _emit_on_the_test_db(monkeypatch, sessions):
    """`emit_notification` opens its own `AsyncSessionLocal`, which is bound to the *app's*
    engine — so without this it writes to the development database rather than the test one. Same
    redirection the attendance notification tests use."""
    from app.features.realtime import runtime

    monkeypatch.setattr(runtime, 'AsyncSessionLocal', sessions)


async def _rows(db, user_id):
    return (
        await db.execute(
            select(Notification).where(
                Notification.user_id == user_id, Notification.type == 'message_reaction'
            )
        )
    ).scalars().all()


async def test_the_toggle_reports_the_sender_so_the_right_person_is_notified(db, factory):
    a, b, message = await _dm(db, factory)
    reacted = await toggle_reaction(
        db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True
    )
    assert reacted.sender_id == a.id, 'the notification would go to the wrong person'
    assert reacted.conversation_id == message.conversation_id


async def test_a_reaction_notification_carries_the_emoji_and_a_deep_link(db, factory):
    a, b, message = await _dm(db, factory)
    await emit_notification(
        user_id=a.id,
        notif_type='message_reaction',
        actor_id=b.id,
        target_type='conversation',
        target_id=message.conversation_id,
        detail=HEART,
    )

    rows = await _rows(db, a.id)
    assert len(rows) == 1
    row = rows[0]
    assert row.actor_id == b.id
    # Without the emoji the push can only say "reacted to your message", which is the version
    # users read as a bug rather than a design.
    assert row.detail == HEART
    # Without the target the row can only open the inbox — the mistake attendance rows made.
    assert (row.target_type, row.target_id) == ('conversation', message.conversation_id)


async def test_repeat_toggling_collapses_into_one_unread_row(db, factory):
    """react → un-react → react is a two-second gesture. Uncollapsed it is three rows and three
    pushes for one person changing their mind."""
    a, b, message = await _dm(db, factory)
    for _ in range(3):
        await emit_notification(
            user_id=a.id,
            notif_type='message_reaction',
            actor_id=b.id,
            target_type='conversation',
            target_id=message.conversation_id,
            detail=THUMB,
            collapse_unread=True,
        )

    assert len(await _rows(db, a.id)) == 1


async def test_collapsing_stops_once_the_first_one_has_been_seen(db, factory):
    """Collapsing on *unread* rather than a time window: once you have actually seen it, a later
    reaction is news again."""
    a, b, message = await _dm(db, factory)
    kwargs = dict(
        user_id=a.id, notif_type='message_reaction', actor_id=b.id,
        target_type='conversation', target_id=message.conversation_id,
        detail=THUMB, collapse_unread=True,
    )
    await emit_notification(**kwargs)

    from datetime import UTC, datetime
    first = (await _rows(db, a.id))[0]
    first.read_at = datetime.now(UTC)
    await db.commit()

    await emit_notification(**kwargs)
    assert len(await _rows(db, a.id)) == 2


async def test_the_duplicate_check_is_scoped_to_actor_and_target(db, factory):
    """Two different people reacting, or the same person reacting in a different conversation,
    are separate events — collapsing those would hide real activity."""
    a, b, message = await _dm(db, factory)
    c = await factory.user(display_name='C')
    await emit_notification(
        user_id=a.id, notif_type='message_reaction', actor_id=b.id,
        target_type='conversation', target_id=message.conversation_id,
        detail=THUMB, collapse_unread=True,
    )

    assert await unread_duplicate_exists(
        db, user_id=a.id, type='message_reaction',
        actor_id=b.id, target_id=message.conversation_id,
    )
    assert not await unread_duplicate_exists(
        db, user_id=a.id, type='message_reaction',
        actor_id=c.id, target_id=message.conversation_id,
    )


def test_a_reaction_is_worth_a_push():
    """Live-only would leave the original gap in place for anyone whose app is closed — which is
    most people, most of the time."""
    assert 'message_reaction' in PUSHABLE_NOTIFICATION_TYPES


def test_the_push_names_the_emoji_but_never_the_message():
    """A push shows on a locked screen, so it says what happened, not what was said — the rule
    every other line of this copy already follows."""
    from app.features.notifications.push import _notification_copy

    title, body = _notification_copy('message_reaction', 'Alex', None, HEART)
    assert title == 'Alex'
    assert HEART in body
    assert 'see you at 5' not in body

    _, generic = _notification_copy('message_reaction', 'Alex', None, None)
    assert 'Reacted to your message' == generic
