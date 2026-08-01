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
