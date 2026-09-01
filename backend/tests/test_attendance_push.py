"""Honors attendance push payload — Phase 5 (non-DB unit tests)."""

from __future__ import annotations

from uuid import uuid4

from app.features.notifications.push import PushSender


def test_send_attendance_open_prunes_only_unregistered(monkeypatch):
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
            _Resp(False, ValueError('transient')),  # → keep
        ]
        success_count = 1
        failure_count = 2

    captured: dict = {}

    def fake_send(message, **_kw):
        captured['data'] = message.data
        return _Batch()

    monkeypatch.setattr(messaging, 'send_each_for_multicast', fake_send)

    session_id = uuid4()
    invalid = sender._send_attendance_open(['t1', 't2', 't3'], session_id)

    assert invalid == ['t2']
    # Deep-link payload carries the session id and type — never the QR secret.
    assert captured['data'] == {'type': 'honors_attendance_open', 'session_id': str(session_id)}


async def test_notify_attendance_open_disabled_sender_is_noop():
    sender = PushSender()  # no FIREBASE_CREDENTIALS_JSON → disabled
    assert sender.enabled is False
    await sender.notify_honors_attendance_open(None, tokens=['t1'], session_id=uuid4())


async def test_notify_attendance_open_noop_without_tokens(monkeypatch):
    sender = PushSender()
    sender._ready = True
    sent = []
    monkeypatch.setattr(sender, '_send_attendance_open', lambda *_a: sent.append(1) or [])
    await sender.notify_honors_attendance_open(None, tokens=[], session_id=uuid4())
    assert sent == []
