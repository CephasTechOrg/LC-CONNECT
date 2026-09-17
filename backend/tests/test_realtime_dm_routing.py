"""DM live-delivery routing: subscribe key must match the publish key.

A DM is addressed by its **match id** but stored under its own `Conversation.id`, and every
server-side publisher routes on the canonical id. The gateway used to index subscribers under
whatever ref the client sent, so DM fan-out went to an empty set and nothing was ever delivered
into an open DM. Groups were unaffected (their ref *is* the conversation id), which is why the
bug looked intermittent rather than total.

These tests drive the handlers directly against real `Connection`s on the module-level manager.
`TestClient` cannot be used here — it deadlocks on concurrent websockets (see
`test_realtime_gateway.py::test_send_emits_conversation_updated_on_user_channel`).
"""

import asyncio
from datetime import UTC, datetime
from uuid import uuid4

import pytest

from app.features.realtime import gateway, protocol, service
from app.features.realtime.runtime import manager
from app.models import Message


class FakeSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []
        self.closed: int | None = None

    async def send_json(self, data: dict) -> None:
        self.sent.append(data)

    async def close(self, code: int = 1000) -> None:
        self.closed = code


class _Conversation:
    """A DM has a conversation id distinct from its match id; a group has match_id None."""

    def __init__(self, *, match_id=None) -> None:
        self.id = uuid4()
        self.kind = 'dm' if match_id else 'group'
        self.match_id = match_id


async def _tick() -> None:
    # Let each connection's writer task drain its outbox onto the socket.
    await asyncio.sleep(0.02)


def _frames(sock: FakeSocket, wanted: str) -> list[dict]:
    return [f for f in sock.sent if f['type'] == wanted]


@pytest.fixture
async def conns():
    """Registered sockets, always torn down so the module-level manager stays clean between
    tests — a leaked subscription would make a later test pass for the wrong reason."""
    created = []

    def make(user_id=None):
        sock = FakeSocket()
        conn = manager.register(sock, user_id or uuid4())
        created.append(conn)
        return conn, sock

    yield make
    for conn in created:
        await manager.unregister(conn)


@pytest.fixture
def routing(monkeypatch):
    """Authorize every ref to one fixed conversation and persist a matching stub message."""

    def install(conversation):
        async def ok_recheck(db, user_id):
            return object()

        # (conversation, members) — see the gateway test for why authorization returns both.
        async def ok_authorize(db, user_id, ref):
            return conversation, [(uuid4(), False)]

        async def ok_members(db, conversation_id, *, exclude=None):
            return [uuid4()]

        async def ok_members_muted(db, conversation_id, *, exclude=None):
            return []  # no other recipients → no user-channel noise, no push scheduling

        async def persist(db, *, sender_id, match_id, conversation_id, body, client_message_id):
            # NOTE: conversation_id is set here on purpose. The older helper in
            # test_realtime_gateway.py leaves it None, which makes addressing_id collapse to the
            # match id and hides exactly the mismatch these tests exist to catch.
            return (
                Message(
                    id=uuid4(),
                    match_id=match_id,
                    conversation_id=conversation_id,
                    sender_id=sender_id,
                    client_message_id=client_message_id,
                    body=body,
                    created_at=datetime.now(UTC),
                    read_at=None,
                ),
                True,
            )

        monkeypatch.setattr(service, 'recheck_account', ok_recheck)
        monkeypatch.setattr(service, 'authorize_conversation', ok_authorize)
        monkeypatch.setattr(gateway, 'active_member_ids', ok_members)
        monkeypatch.setattr(gateway, 'persist_message_idempotent', persist)

    return install


async def _subscribe(conn, ref):
    await gateway._on_subscribe(conn, protocol.SubscribeFrame(
        type='conversation.subscribe', request_id=uuid4(), conversation_id=ref,
    ))


async def _send(conn, ref, body='hi'):
    await gateway._on_send(conn, protocol.SendFrame(
        type='message.send', request_id=uuid4(), conversation_id=ref,
        client_message_id=uuid4(), body=body,
    ))


# ── the headline gap ──────────────────────────────────────────────────────────

async def test_dm_message_created_reaches_partner_subscribed_by_match_id(conns, routing):
    """The reported bug: B has the DM open, A sends, B must see it without leaving the chat."""
    match_id = uuid4()
    conversation = _Conversation(match_id=match_id)
    routing(conversation)

    conn_a, _ = conns()
    conn_b, sock_b = conns()

    await _subscribe(conn_b, match_id)       # B opens the chat, addressing it by match id
    await _send(conn_a, match_id)            # A sends, addressing it the same way
    await _tick()

    created = _frames(sock_b, 'message.created')
    assert len(created) == 1, 'partner with the DM open received no live message'
    # Addressed by match id so the client's open-chat guard matches it.
    assert created[0]['conversation_id'] == str(match_id)
    assert created[0]['message']['body'] == 'hi'


async def test_group_message_created_still_reaches_subscriber(conns, routing):
    """Groups address the conversation directly — the identity path must not regress."""
    conversation = _Conversation()  # group: match_id is None
    routing(conversation)

    conn_a, _ = conns()
    conn_b, sock_b = conns()

    await _subscribe(conn_b, conversation.id)
    await _send(conn_a, conversation.id, body='group hi')
    await _tick()

    created = _frames(sock_b, 'message.created')
    assert len(created) == 1
    assert created[0]['conversation_id'] == str(conversation.id)


async def test_dm_subscribed_by_conversation_id_also_receives(conns, routing):
    """`resolve_conversation` tries the conversation table first, so a DM may legitimately be
    addressed by its conversation id. Canonicalising must handle both, not special-case one."""
    conversation = _Conversation(match_id=uuid4())
    routing(conversation)

    conn_a, _ = conns()
    conn_b, sock_b = conns()

    await _subscribe(conn_b, conversation.id)
    await _send(conn_a, conversation.id)
    await _tick()

    assert len(_frames(sock_b, 'message.created')) == 1


# ── regressions this refactor most easily causes ──────────────────────────────

async def test_read_receipt_reaches_dm_partner(conns, routing, monkeypatch):
    """Receipts worked before only because both sides used the client ref. Now the routing key
    is canonical and the payload id is the addressing id — both must be right."""
    match_id = uuid4()
    conversation = _Conversation(match_id=match_id)
    routing(conversation)

    read_at = datetime.now(UTC)

    # `conversation` is passed by the gateway so the boundary write does not re-resolve what
    # authorization already loaded. A stub that omits it silently breaks the seam.
    async def ok_mark_read(db, *, reader_id, match_id, through_message_id, conversation=None):
        return read_at

    monkeypatch.setattr(service, 'mark_read', ok_mark_read)

    conn_a, _ = conns()
    conn_b, sock_b = conns()

    await _subscribe(conn_b, match_id)
    await gateway._on_read(conn_a, protocol.ReadFrame(
        type='messages.read', conversation_id=match_id, through_message_id=uuid4(),
    ))
    await _tick()

    receipts = _frames(sock_b, 'messages.receipt')
    assert len(receipts) == 1
    assert receipts[0]['conversation_id'] == str(match_id)


async def test_typing_uses_addressing_id_for_dm(conns, routing, monkeypatch):
    """Group typing keeps working by identity even if canonicalisation is missed here, so this
    DM-specific assertion is the only thing guarding the asymmetry."""
    match_id = uuid4()
    conversation = _Conversation(match_id=match_id)
    routing(conversation)

    conn_a, _ = conns()
    await _subscribe(conn_a, match_id)

    calls = []

    async def fake_publish_to_user(user_id, frame):
        calls.append(frame)

    monkeypatch.setattr(gateway.event_bus, 'publish_to_user', fake_publish_to_user)

    await gateway._on_typing(conn_a, match_id, active=True)

    assert len(calls) == 1
    assert calls[0]['type'] == 'typing'
    assert calls[0]['conversation_id'] == str(match_id)


async def test_unsubscribe_by_match_id_clears_canonical_subscription(conns, routing):
    """A ref-keyed unsubscribe must detach the canonical index, or the socket keeps receiving."""
    match_id = uuid4()
    conversation = _Conversation(match_id=match_id)
    routing(conversation)

    conn, _ = conns()
    await _subscribe(conn, match_id)
    assert manager.conversation_subscriber_count(conversation.id) == 1

    gateway._on_unsubscribe(conn, protocol.UnsubscribeFrame(
        type='conversation.unsubscribe', conversation_id=match_id,
    ))

    assert manager.conversation_subscriber_count(conversation.id) == 0
    assert conn.partners == {}
    assert conn.refs == {}
    assert conn.addressing == {}


async def test_delivery_receipt_reaches_dm_partner(conns, routing, monkeypatch):
    """Protocol 2's second tick. Same routing asymmetry as the read receipt above: canonical id
    to route, addressing id in the payload — the sender's open chat matches on the latter."""
    match_id = uuid4()
    conversation = _Conversation(match_id=match_id)
    routing(conversation)

    delivered_at = datetime.now(UTC)

    async def ok_mark_delivered(
        db, *, recipient_id, match_id, through_message_id, conversation=None
    ):
        return delivered_at

    monkeypatch.setattr(service, 'mark_delivered', ok_mark_delivered)

    conn_a, _ = conns()
    conn_b, sock_b = conns()

    await _subscribe(conn_b, match_id)
    await gateway._on_delivered(conn_a, protocol.DeliveredFrame(
        type='messages.delivered', conversation_id=match_id, through_message_id=uuid4(),
    ))
    await _tick()

    receipts = _frames(sock_b, 'messages.delivery')
    assert len(receipts) == 1
    assert receipts[0]['conversation_id'] == str(match_id)
    assert receipts[0]['user_id'] == str(conn_a.user_id)


async def test_delivery_receipt_is_not_echoed_to_the_acknowledger(conns, routing, monkeypatch):
    """The recipient does not need its own tick, and echoing it would make the *recipient's* copy
    of its own earlier messages appear delivered by itself."""
    match_id = uuid4()
    routing(_Conversation(match_id=match_id))

    async def ok_mark_delivered(
        db, *, recipient_id, match_id, through_message_id, conversation=None
    ):
        return datetime.now(UTC)

    monkeypatch.setattr(service, 'mark_delivered', ok_mark_delivered)

    conn_a, sock_a = conns()
    await _subscribe(conn_a, match_id)
    await gateway._on_delivered(conn_a, protocol.DeliveredFrame(
        type='messages.delivered', conversation_id=match_id, through_message_id=uuid4(),
    ))
    await _tick()

    assert _frames(sock_a, 'messages.delivery') == []


async def test_delivery_that_does_not_apply_publishes_nothing(conns, routing, monkeypatch):
    """`mark_delivered` returns None for an unknown conversation, a message from another
    conversation, or a non-member. Publishing a receipt anyway would show a tick for a delivery
    that was never recorded — the one thing worse than a missing tick."""
    match_id = uuid4()
    routing(_Conversation(match_id=match_id))

    async def no_op(db, *, recipient_id, match_id, through_message_id, conversation=None):
        return None

    monkeypatch.setattr(service, 'mark_delivered', no_op)

    conn_a, _ = conns()
    conn_b, sock_b = conns()
    await _subscribe(conn_b, match_id)
    await gateway._on_delivered(conn_a, protocol.DeliveredFrame(
        type='messages.delivered', conversation_id=match_id, through_message_id=uuid4(),
    ))
    await _tick()

    assert _frames(sock_b, 'messages.delivery') == []


async def test_group_delivery_ack_is_dropped_before_any_write(conns, routing, monkeypatch):
    """The quadratic case.

    A group bubble shows no delivered tick, but every member's device acknowledges every message.
    One message in a 30-member group therefore produced 29 acknowledgements, each costing an
    account recheck, an authorization, four further queries and a fan-out to all 30 sockets —
    roughly 170 queries and 870 socket writes to drive a glyph that is never drawn.

    Enforced server-side because the client cannot be trusted to keep suppressing it: an older
    build, or a modified one, would reintroduce the whole cost.
    """
    conversation_id = uuid4()
    routing(_Conversation())  # match_id None ⇒ kind 'group'

    calls = []

    async def spy(db, *, recipient_id, match_id, through_message_id, conversation=None):
        calls.append(match_id)
        return datetime.now(UTC)

    monkeypatch.setattr(service, 'mark_delivered', spy)

    conn_a, _ = conns()
    conn_b, sock_b = conns()
    await _subscribe(conn_b, conversation_id)
    await gateway._on_delivered(conn_a, protocol.DeliveredFrame(
        type='messages.delivered', conversation_id=conversation_id,
        through_message_id=uuid4(),
    ))
    await _tick()

    assert calls == [], 'no boundary write for a group'
    assert _frames(sock_b, 'messages.delivery') == [], 'and no fan-out either'


async def test_group_read_receipt_is_still_delivered(conns, routing, monkeypatch):
    """Read is *not* suppressed for groups — it drives unread counts, which groups very much
    have. Only the cosmetic delivery tick is DM-only, and conflating the two would silently break
    group unread."""
    conversation_id = uuid4()
    routing(_Conversation())  # group

    async def ok_mark_read(db, *, reader_id, match_id, through_message_id, conversation=None):
        return datetime.now(UTC)

    monkeypatch.setattr(service, 'mark_read', ok_mark_read)

    conn_a, _ = conns()
    conn_b, sock_b = conns()
    await _subscribe(conn_b, conversation_id)
    await gateway._on_read(conn_a, protocol.ReadFrame(
        type='messages.read', conversation_id=conversation_id, through_message_id=uuid4(),
    ))
    await _tick()

    assert len(_frames(sock_b, 'messages.receipt')) == 1
