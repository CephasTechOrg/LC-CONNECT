"""WebSocket gateway end-to-end over TestClient.

DB-free: the service functions that touch Postgres (authenticate, recheck_account,
authorize_conversation, persist) are monkeypatched, so we exercise the real gateway
lifecycle, protocol, manager, and rate limiting without a database.
"""

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from starlette.websockets import WebSocketDisconnect

from app.features.realtime import service
from app.features.realtime.protocol import CloseCode
from app.main import app
from app.models import Message


class _User:
    def __init__(self) -> None:
        self.id = uuid4()


class _Match:
    def __init__(self, user_a_id, user_b_id) -> None:
        self.user_a_id = user_a_id
        self.user_b_id = user_b_id


class _Conversation:
    def __init__(self, *, kind='dm', match_id=None) -> None:
        self.id = uuid4()
        self.kind = kind
        self.match_id = match_id or uuid4()


def _recv_type(ws, wanted, tries=6):
    """Read frames until one of `wanted` type arrives (skips interleaved events)."""
    for _ in range(tries):
        frame = ws.receive_json()
        if frame['type'] == wanted:
            return frame
    raise AssertionError(f'did not receive {wanted}')


def _make_message(match_id, sender_id, client_message_id, body):
    return Message(
        id=uuid4(),
        match_id=match_id,
        sender_id=sender_id,
        client_message_id=client_message_id,
        body=body,
        created_at=datetime.now(UTC),
        read_at=None,
    )


@pytest.fixture
def happy_auth(monkeypatch):
    """authenticate/recheck/authorize all succeed for a fixed user; the conversation has one
    other member (a DM). Keeps the gateway tests DB-free."""
    user = _User()
    partner_id = uuid4()

    async def ok_authenticate(db, token):
        return user

    async def ok_recheck(db, user_id):
        return user

    async def ok_authorize(db, user_id, match_id):
        return _Conversation(kind='dm', match_id=match_id)

    async def ok_members(db, conversation_id, *, exclude=None):
        return [partner_id]

    monkeypatch.setattr(service, 'authenticate', ok_authenticate)
    monkeypatch.setattr(service, 'recheck_account', ok_recheck)
    monkeypatch.setattr(service, 'authorize_conversation', ok_authorize)
    monkeypatch.setattr('app.features.realtime.gateway.active_member_ids', ok_members)
    return user


def _client():
    from fastapi.testclient import TestClient

    return TestClient(app)


# ── authentication ────────────────────────────────────────────────────────────

def test_auth_ok(happy_auth):
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'auth', 'access_token': 'good'})
        frame = ws.receive_json()
    assert frame['type'] == 'auth.ok'
    assert frame['user_id'] == str(happy_auth.id)


def test_auth_failed_closes(monkeypatch):
    async def bad(db, token):
        raise service.WsAuthFailed('nope')

    monkeypatch.setattr(service, 'authenticate', bad)
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'auth', 'access_token': 'bad'})
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == CloseCode.AUTH_FAILED


def test_unverified_forbidden_closes(monkeypatch):
    async def forbidden(db, token):
        raise service.WsForbidden('unverified')

    monkeypatch.setattr(service, 'authenticate', forbidden)
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'auth', 'access_token': 'x'})
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == CloseCode.FORBIDDEN


def test_non_auth_first_frame_closes(happy_auth):
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'conversation.subscribe', 'request_id': str(uuid4()), 'conversation_id': str(uuid4())})
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == CloseCode.AUTH_FAILED


# ── dispatch ──────────────────────────────────────────────────────────────────

def test_subscribe_then_forbidden(happy_auth, monkeypatch):
    conv = uuid4()
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'auth', 'access_token': 'good'})
        assert ws.receive_json()['type'] == 'auth.ok'

        ws.send_json({'type': 'conversation.subscribe', 'request_id': str(uuid4()), 'conversation_id': str(conv)})
        assert ws.receive_json()['type'] == 'subscribed'

        # Now authorization starts failing (e.g. a block landed).
        async def denied(db, user_id, match_id):
            raise service.WsForbidden('blocked')

        monkeypatch.setattr(service, 'authorize_conversation', denied)
        ws.send_json({'type': 'conversation.subscribe', 'request_id': str(uuid4()), 'conversation_id': str(uuid4())})
        frame = ws.receive_json()
    assert frame['type'] == 'error' and frame['code'] == 'forbidden'


def test_duplicate_send_returns_same_ack(happy_auth, monkeypatch):
    cache: dict = {}

    async def fake_persist(db, *, sender_id, match_id, conversation_id, body, client_message_id):
        created = client_message_id not in cache
        if created:
            cache[client_message_id] = _make_message(match_id, sender_id, client_message_id, body)
        return cache[client_message_id], created

    monkeypatch.setattr('app.features.realtime.gateway.persist_message_idempotent', fake_persist)

    conv, cmid = uuid4(), uuid4()
    payload = {
        'type': 'message.send',
        'request_id': str(uuid4()),
        'conversation_id': str(conv),
        'client_message_id': str(cmid),
        'body': 'hello',
    }
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'auth', 'access_token': 'good'})
        assert ws.receive_json()['type'] == 'auth.ok'

        ws.send_json(payload)
        ack1 = _recv_type(ws, 'message.ack')  # skips the conversation.updated frame
        ws.send_json({**payload, 'request_id': str(uuid4())})
        ack2 = _recv_type(ws, 'message.ack')

    assert ack1['duplicate'] is False
    assert ack2['duplicate'] is True
    assert ack1['message']['id'] == ack2['message']['id']  # idempotent


def test_send_emits_conversation_updated_on_user_channel(happy_auth, monkeypatch):
    # A single socket avoids TestClient's concurrent-websocket deadlock; the gateway
    # publishes conversation.updated to BOTH participants' user channels, so the sender
    # receives it on its own user channel — proving publish_to_user is wired.
    async def persist(db, *, sender_id, match_id, conversation_id, body, client_message_id):
        return _make_message(match_id, sender_id, client_message_id, body), True

    monkeypatch.setattr('app.features.realtime.gateway.persist_message_idempotent', persist)

    conv = uuid4()
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'auth', 'access_token': 'good'})
        assert ws.receive_json()['type'] == 'auth.ok'
        ws.send_json({
            'type': 'message.send',
            'request_id': str(uuid4()),
            'conversation_id': str(conv),
            'client_message_id': str(uuid4()),
            'body': 'hi',
        })
        updated = _recv_type(ws, 'conversation.updated')

    assert updated['conversation_id'] == str(conv)
    assert updated['message']['body'] == 'hi'


async def test_typing_routes_to_partner_user_channel(monkeypatch):
    from app.features.realtime import gateway
    from app.features.realtime.manager import Connection

    class _Sock:
        async def send_json(self, data):
            pass

        async def close(self, code=1000):
            pass

    me, partner, conv = uuid4(), uuid4(), uuid4()
    conn = Connection(_Sock(), me, outbox_max=8)
    conn.partners[conv] = partner  # populated at subscribe

    calls = []

    async def fake_publish_to_user(user_id, frame):
        calls.append((user_id, frame))

    monkeypatch.setattr(gateway.event_bus, 'publish_to_user', fake_publish_to_user)

    await gateway._on_typing(conn, conv, active=True)
    assert calls, 'typing should be delivered'
    assert calls[0][0] == partner
    assert calls[0][1]['type'] == 'typing' and calls[0][1]['active'] is True

    # Unknown/unsubscribed conversation → no partner cached → no-op.
    calls.clear()
    await gateway._on_typing(conn, uuid4(), active=True)
    assert calls == []


def test_malformed_frame_gets_error(happy_auth):
    with _client().websocket_connect('/api/v1/ws') as ws:
        ws.send_json({'type': 'auth', 'access_token': 'good'})
        assert ws.receive_json()['type'] == 'auth.ok'
        ws.send_json({'type': 'totally-unknown'})
        frame = ws.receive_json()
    assert frame['type'] == 'error' and frame['code'] == 'invalid_frame'
