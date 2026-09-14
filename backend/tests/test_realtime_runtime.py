"""Selective notification push — the offline-check + grace-window gate in
`_schedule_notification_push`, and the exact set of notification types that qualify."""

from __future__ import annotations

from unittest.mock import AsyncMock
from uuid import uuid4

from app.features.realtime import runtime


def test_pushable_notification_types_is_the_agreed_small_set():
    """Locks the deliberately narrow set — connections, group invites/requests, program
    membership verification, and admin membership invites. Adding a type here is a product
    decision, not something that should drift silently."""
    assert runtime.PUSHABLE_NOTIFICATION_TYPES == {
        'connection_request',
        'connection_accepted',
        'group_invite',
        'group_join_request',
        'group_request_approved',
        'program_membership_verified',
        'admin_membership_invited',
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
