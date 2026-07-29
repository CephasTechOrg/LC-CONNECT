"""Device registration endpoints + FCM push sender (mocked firebase)."""

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import require_verified_student
from app.features.notifications.push import PushSender, _notification_copy
from app.main import app


class _User:
    def __init__(self) -> None:
        self.id = uuid4()


async def _fake_db():
    # AsyncMock session: execute/commit are awaitable no-ops (no real Postgres).
    yield AsyncMock()


@pytest.fixture(autouse=True)
def _clear_overrides():
    yield
    app.dependency_overrides.clear()


def _authed_client(user):
    app.dependency_overrides[require_verified_student] = lambda: user
    app.dependency_overrides[get_db] = _fake_db
    return TestClient(app)


# ── /devices endpoints ────────────────────────────────────────────────────────

def test_register_device_returns_204():
    resp = _authed_client(_User()).post('/api/v1/devices', json={'token': 'tok', 'platform': 'ios'})
    assert resp.status_code == 204


def test_register_device_rejects_bad_platform():
    resp = _authed_client(_User()).post('/api/v1/devices', json={'token': 'tok', 'platform': 'windows'})
    assert resp.status_code == 422


def test_unregister_device_returns_204():
    resp = _authed_client(_User()).delete('/api/v1/devices/sometoken')
    assert resp.status_code == 204


# ── PushSender ────────────────────────────────────────────────────────────────

async def test_disabled_sender_is_noop():
    sender = PushSender()  # no FIREBASE_CREDENTIALS_JSON → disabled
    assert sender.enabled is False
    # Returns immediately without touching the db (which is None here).
    await sender.notify_new_message(
        None, recipient_id=uuid4(), sender_name='X', conversation_id=uuid4(), sender_id=uuid4()
    )


def test_send_prunes_only_unregistered_tokens(monkeypatch):
    from firebase_admin import messaging

    sender = PushSender()
    sender._ready = True  # pretend configured

    class _Resp:
        def __init__(self, ok, exc=None):
            self.success = ok
            self.exception = exc

    class _Batch:
        responses = [
            _Resp(True),
            _Resp(False, messaging.UnregisteredError('gone')),  # → prune
            _Resp(False, ValueError('transient')),  # → keep (not unregistered)
        ]
        success_count = 1
        failure_count = 2

    monkeypatch.setattr(messaging, 'send_each_for_multicast', lambda _m, **_kw: _Batch())
    invalid = sender._send(['t1', 't2', 't3'], 'Sender', uuid4(), uuid4())
    assert invalid == ['t2']


async def test_notify_prunes_invalid_via_flow(monkeypatch):
    sender = PushSender()
    sender._ready = True
    monkeypatch.setattr('app.features.notifications.push.tokens_for_user', AsyncMock(return_value=['t1', 't2']))
    pruned: list[str] = []

    async def fake_prune(_db, tokens):
        pruned.extend(tokens)

    monkeypatch.setattr('app.features.notifications.push.prune_tokens', fake_prune)
    monkeypatch.setattr(sender, '_send', lambda *_a: ['t2'])  # t2 came back invalid

    await sender.notify_new_message(
        None, recipient_id=uuid4(), sender_name='N', conversation_id=uuid4(), sender_id=uuid4()
    )
    assert pruned == ['t2']


async def test_notify_noop_when_no_tokens(monkeypatch):
    sender = PushSender()
    sender._ready = True
    monkeypatch.setattr('app.features.notifications.push.tokens_for_user', AsyncMock(return_value=[]))
    sent = []
    monkeypatch.setattr(sender, '_send', lambda *_a: sent.append(1) or [])
    await sender.notify_new_message(
        None, recipient_id=uuid4(), sender_name='N', conversation_id=uuid4(), sender_id=uuid4()
    )
    assert sent == []  # no tokens → never calls FCM


# ── notify_in_app_event (the selective connections/groups push) ───────────────


@pytest.mark.parametrize(
    ('notif_type', 'actor_name', 'group_name', 'expected_title', 'expected_body_contains'),
    [
        ('connection_request', 'Alex', None, 'Alex', 'connect'),
        ('connection_accepted', 'Alex', None, 'Alex', 'Accepted'),
        ('group_invite', 'Alex', 'Chess Club', 'Alex', 'Chess Club'),
        ('group_invite', 'Alex', None, 'Alex', 'a group'),
        ('group_join_request', 'Alex', 'Chess Club', 'Alex', 'Chess Club'),
        ('group_request_approved', 'Alex', 'Chess Club', 'Chess Club', 'approved'),
        ('group_request_approved', 'Alex', None, 'Group request', 'approved'),
    ],
)
def test_notification_copy_per_type(notif_type, actor_name, group_name, expected_title, expected_body_contains):
    title, body = _notification_copy(notif_type, actor_name, group_name)
    assert title == expected_title
    assert expected_body_contains in body


def test_notification_copy_falls_back_when_actor_missing():
    title, _ = _notification_copy('connection_request', None, None)
    assert title == 'Someone'


async def test_notify_in_app_event_disabled_sender_is_noop():
    sender = PushSender()  # no FIREBASE_CREDENTIALS_JSON → disabled
    await sender.notify_in_app_event(
        None, recipient_id=uuid4(), notif_type='connection_request', actor_name='X', group_name=None
    )


async def test_notify_in_app_event_prunes_invalid_via_flow(monkeypatch):
    sender = PushSender()
    sender._ready = True
    monkeypatch.setattr('app.features.notifications.push.tokens_for_user', AsyncMock(return_value=['t1', 't2']))
    pruned: list[str] = []

    async def fake_prune(_db, tokens):
        pruned.extend(tokens)

    monkeypatch.setattr('app.features.notifications.push.prune_tokens', fake_prune)
    monkeypatch.setattr(sender, '_send_notification', lambda *_a: ['t2'])

    await sender.notify_in_app_event(
        None, recipient_id=uuid4(), notif_type='group_invite', actor_name='Alex', group_name='Chess Club'
    )
    assert pruned == ['t2']


async def test_notify_in_app_event_noop_when_no_tokens(monkeypatch):
    sender = PushSender()
    sender._ready = True
    monkeypatch.setattr('app.features.notifications.push.tokens_for_user', AsyncMock(return_value=[]))
    sent = []
    monkeypatch.setattr(sender, '_send_notification', lambda *_a: sent.append(1) or [])
    await sender.notify_in_app_event(
        None, recipient_id=uuid4(), notif_type='connection_accepted', actor_name='Alex', group_name=None
    )
    assert sent == []
