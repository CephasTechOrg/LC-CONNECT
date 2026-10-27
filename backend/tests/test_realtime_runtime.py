"""Selective notification push — the offline-check + grace-window gate in
`_schedule_notification_push`, and the exact set of notification types that qualify."""

from __future__ import annotations

from unittest.mock import AsyncMock
from uuid import uuid4

from app.features.realtime import runtime


def test_pushable_notification_types_is_the_agreed_small_set():
    """Locks the deliberately narrow set — connections, group invites/requests, program
    membership verification, admin membership invites, and a reaction to your own message.
    Adding a type here is a product decision, not something that should drift silently.

    `message_reaction` was added deliberately. Reactions fan out only on the conversation
    channel, which reaches nobody who does not have that chat open — so without a push the
    feature was invisible to anyone whose app was closed, which is most people most of the time.
    It fires only for the message's sender, only on add, and collapses while unread, so one
    person changing their mind is still one interruption.
    """
    assert runtime.PUSHABLE_NOTIFICATION_TYPES == {
        'connection_request',
        'connection_accepted',
        'group_invite',
        'group_join_request',
        'group_request_approved',
        'program_membership_verified',
        'admin_membership_invited',
        'message_reaction',
        'scholar_profile_approved',
        'scholar_profile_changes_requested',
        'scholar_profile_revoked',
    }


async def test_schedule_notification_push_fires_when_still_offline(monkeypatch):
    monkeypatch.setattr(runtime.settings, 'push_reconnect_grace_seconds', 0)
    monkeypatch.setattr(runtime.manager, 'user_socket_count', lambda _uid: 0)
    called = {}

    async def fake_notify(_db, **kwargs):
        called.update(kwargs)

    monkeypatch.setattr(runtime.push_sender, 'notify_in_app_event', fake_notify)

    user_id = uuid4()
    await runtime._schedule_notification_push(user_id, 'group_invite', 'Alex', 'Chess Club')

    assert called['recipient_id'] == user_id
    assert called['notif_type'] == 'group_invite'
    assert called['actor_name'] == 'Alex'
    assert called['group_name'] == 'Chess Club'


async def test_schedule_notification_push_skips_when_reconnected(monkeypatch):
    monkeypatch.setattr(runtime.settings, 'push_reconnect_grace_seconds', 0)
    monkeypatch.setattr(runtime.manager, 'user_socket_count', lambda _uid: 1)  # back online
    fake_notify = AsyncMock()
    monkeypatch.setattr(runtime.push_sender, 'notify_in_app_event', fake_notify)

    await runtime._schedule_notification_push(uuid4(), 'connection_accepted', 'Alex', None)

    fake_notify.assert_not_called()


# ── delete fan-out: canonical routing, client-facing addressing ───────────────

async def test_broadcast_message_deleted_routes_canonical_and_addresses_by_match_id(monkeypatch):
    """A DM delete must be *routed* on the conversation id (what the manager indexes) but
    *addressed* with the match id (what the client's open-chat guard matches). Passing the raw
    conversation id, as the caller used to, got both wrong at once."""
    from datetime import UTC, datetime

    from app.models import Message

    match_id, conversation_id, member_id = uuid4(), uuid4(), uuid4()
    message = Message(
        id=uuid4(),
        match_id=match_id,
        conversation_id=conversation_id,
        sender_id=uuid4(),
        body='gone',
        created_at=datetime.now(UTC),
    )

    conversation_calls: list[tuple] = []
    user_calls: list[tuple] = []

    async def fake_to_conversation(cid, frame, exclude_user=None):
        conversation_calls.append((cid, frame))

    async def fake_to_user(uid, frame):
        user_calls.append((uid, frame))

    monkeypatch.setattr(runtime.event_bus, 'publish_to_conversation', fake_to_conversation)
    monkeypatch.setattr(runtime.event_bus, 'publish_to_user', fake_to_user)

    await runtime.broadcast_message_deleted(message, [member_id])

    assert len(conversation_calls) == 1
    routed_id, frame = conversation_calls[0]
    assert routed_id == conversation_id, 'delete must route on the canonical conversation id'
    assert frame['conversation_id'] == str(match_id), 'frame must carry the addressing id'
    assert frame['message_id'] == str(message.id)
    assert user_calls == [(member_id, frame)]


# ── reaction inbox signal: author's user channel, add-only ────────────────────

async def test_emit_reaction_activity_reaches_only_the_authors_user_channel(monkeypatch):
    """The inbox half of reactions: a frame to the *author's* user channel so their thread row
    updates even with the chat closed. The conversation channel already covers an open chat, so
    this must not touch it — only the user channel, only the author."""
    sender_id, actor_id, addressing_id, message_id = uuid4(), uuid4(), uuid4(), uuid4()

    user_calls: list[tuple] = []
    conversation_calls: list[tuple] = []

    async def fake_to_user(uid, frame):
        user_calls.append((uid, frame))

    async def fake_to_conversation(cid, frame, exclude_user=None):
        conversation_calls.append((cid, frame))

    monkeypatch.setattr(runtime.event_bus, 'publish_to_user', fake_to_user)
    monkeypatch.setattr(runtime.event_bus, 'publish_to_conversation', fake_to_conversation)

    await runtime.emit_reaction_activity(
        sender_id=sender_id,
        actor_id=actor_id,
        addressing_id=addressing_id,
        message_id=message_id,
        emoji='👍',
    )

    assert conversation_calls == [], 'the inbox signal must not re-fan on the conversation channel'
    assert len(user_calls) == 1
    target, frame = user_calls[0]
    assert target == sender_id, 'the signal goes to the message author, not the reactor'
    assert frame['type'] == 'messages.reaction_activity'
    assert frame['conversation_id'] == str(addressing_id)
    assert frame['message_id'] == str(message_id)
    assert frame['actor_id'] == str(actor_id)
    assert frame['emoji'] == '👍'
    assert 'reacted_at' in frame


async def test_broadcast_message_deleted_for_group_uses_conversation_id_for_both(monkeypatch):
    """Groups have no match id, so routing and addressing coincide — the identity path."""
    from datetime import UTC, datetime

    from app.models import Message

    conversation_id = uuid4()
    message = Message(
        id=uuid4(),
        match_id=None,
        conversation_id=conversation_id,
        sender_id=uuid4(),
        body='gone',
        created_at=datetime.now(UTC),
    )

    calls: list[tuple] = []

    async def fake_to_conversation(cid, frame, exclude_user=None):
        calls.append((cid, frame))

    async def noop(uid, frame):
        pass

    monkeypatch.setattr(runtime.event_bus, 'publish_to_conversation', fake_to_conversation)
    monkeypatch.setattr(runtime.event_bus, 'publish_to_user', noop)

    await runtime.broadcast_message_deleted(message, [])

    routed_id, frame = calls[0]
    assert routed_id == conversation_id
    assert frame['conversation_id'] == str(conversation_id)
