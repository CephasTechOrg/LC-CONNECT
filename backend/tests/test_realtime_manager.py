"""ConnectionManager + Connection: indices, delivery, backpressure, revocation."""

import asyncio
from uuid import uuid4

from app.features.realtime.manager import Connection, ConnectionManager


class FakeSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []
        self.closed: int | None = None

    async def send_json(self, data: dict) -> None:
        self.sent.append(data)

    async def close(self, code: int = 1000) -> None:
        self.closed = code


async def _tick() -> None:
    # Let each connection's writer task drain its outbox.
    await asyncio.sleep(0.02)


# ── backpressure (pure, no writer) ────────────────────────────────────────────

def test_enqueue_drops_connection_on_overflow():
    conn = Connection(FakeSocket(), uuid4(), outbox_max=2)  # writer NOT started → never drains
    assert conn.enqueue({'n': 1}) is True
    assert conn.enqueue({'n': 2}) is True
    assert conn.enqueue({'n': 3}) is False  # full → dropped
    assert conn.alive is False
    assert conn.enqueue({'n': 4}) is False  # stays dead


# ── registration + delivery ───────────────────────────────────────────────────

async def test_register_and_deliver():
    mgr = ConnectionManager(outbox_max=16)
    user_a, user_b, conv = uuid4(), uuid4(), uuid4()
    sock_a, sock_b = FakeSocket(), FakeSocket()
    conn_a = mgr.register(sock_a, user_a)
    conn_b = mgr.register(sock_b, user_b)
    mgr.subscribe(conn_a, conv)
    mgr.subscribe(conn_b, conv)

    reached = await mgr.deliver_to_conversation(conv, {'type': 'message.created'}, exclude_user=user_a)
    await _tick()

    assert reached == 1
    assert sock_b.sent == [{'type': 'message.created'}]
    assert sock_a.sent == []  # excluded sender
    await mgr.unregister(conn_a)
    await mgr.unregister(conn_b)


async def test_broadcast_reaches_every_connected_socket():
    mgr = ConnectionManager(outbox_max=16)
    user_a, user_b = uuid4(), uuid4()
    sock_a, sock_b = FakeSocket(), FakeSocket()
    conn_a = mgr.register(sock_a, user_a)
    conn_b = mgr.register(sock_b, user_b)

    frame = {'type': 'announcement', 'audience': 'all'}
    delivered = mgr.broadcast(frame)
    await _tick()

    assert delivered == 2  # both users' sockets
    assert sock_a.sent == [frame]
    assert sock_b.sent == [frame]
    await mgr.unregister(conn_a)
    await mgr.unregister(conn_b)


async def test_unregister_cleans_indices():
    mgr = ConnectionManager()
    user, conv = uuid4(), uuid4()
    conn = mgr.register(FakeSocket(), user)
    mgr.subscribe(conn, conv)
    assert mgr.total_connections == 1
    assert mgr.conversation_subscriber_count(conv) == 1
    await mgr.unregister(conn)
    assert mgr.total_connections == 0
    assert mgr.conversation_subscriber_count(conv) == 0
    assert mgr.user_socket_count(user) == 0


async def test_deliver_to_empty_conversation_is_noop():
    mgr = ConnectionManager()
    assert await mgr.deliver_to_conversation(uuid4(), {'x': 1}) == 0



async def test_deliver_to_user_reaches_all_their_devices():
    mgr = ConnectionManager()
    user, other = uuid4(), uuid4()
    sock1, sock2 = FakeSocket(), FakeSocket()
    mgr.register(sock1, user)
    mgr.register(sock2, user)
    other_conn = mgr.register(FakeSocket(), other)

    reached = mgr.deliver_to_user(user, {'type': 'conversation.updated'})
    await _tick()

    assert reached == 2
    assert sock1.sent and sock2.sent
    assert mgr.deliver_to_user(uuid4(), {'x': 1}) == 0  # unknown user → noop
    await mgr.unregister(other_conn)


# ── revocation ────────────────────────────────────────────────────────────────

async def test_revoke_pair_only_revokes_listed_conversations():
    mgr = ConnectionManager()
    user_a, user_b = uuid4(), uuid4()
    dm_conv, group_conv = uuid4(), uuid4()
    sock_a, sock_b = FakeSocket(), FakeSocket()
    conn_a, conn_b = mgr.register(sock_a, user_a), mgr.register(sock_b, user_b)
    mgr.subscribe(conn_a, dm_conv)
    mgr.subscribe(conn_b, dm_conv)
    mgr.subscribe(conn_a, group_conv)
    mgr.subscribe(conn_b, group_conv)

    await mgr.revoke_pair(
        user_a, user_b, {'type': 'error', 'code': 'forbidden'}, conversation_ids=[dm_conv]
    )
    await _tick()

    assert dm_conv not in conn_a.subscriptions
    assert dm_conv not in conn_b.subscriptions
    assert group_conv in conn_a.subscriptions
    assert group_conv in conn_b.subscriptions
    await mgr.unregister(conn_a)
    await mgr.unregister(conn_b)


async def test_revoke_pair_noop_when_not_shared():
    mgr = ConnectionManager()
    user = uuid4()
    sock1, sock2 = FakeSocket(), FakeSocket()
    mgr.register(sock1, user)
    mgr.register(sock2, user)
    assert mgr.user_socket_count(user) == 2

    await mgr.close_user(user, {'type': 'error', 'code': 'suspended'}, code=4403)
    assert mgr.user_socket_count(user) == 0
    assert sock1.closed == 4403
    assert sock2.closed == 4403


async def test_reap_idle_closes_stale_sockets_only():
    import time

    from app.features.realtime.protocol import CloseCode

    mgr = ConnectionManager()
    fresh_sock, stale_sock = FakeSocket(), FakeSocket()
    fresh = mgr.register(fresh_sock, uuid4())
    stale = mgr.register(stale_sock, uuid4())
    # Make `stale` look idle beyond the cutoff; keep `fresh` current.
    stale.last_seen = time.monotonic() - 120
    mgr.touch(fresh)

    closed = await mgr.reap_idle(idle_seconds=60, code=CloseCode.IDLE_TIMEOUT)
    await _tick()

    assert closed == 1
    assert mgr.total_connections == 1
    assert stale_sock.closed == CloseCode.IDLE_TIMEOUT
    assert stale_sock.sent and stale_sock.sent[-1]['code'] == 'idle_timeout'
    assert fresh_sock.closed is None
    await mgr.unregister(fresh)


async def test_revoke_pair_noop_when_not_shared():
    mgr = ConnectionManager()
    user_a, user_b = uuid4(), uuid4()
    conn_a = mgr.register(FakeSocket(), user_a)
    conn_b = mgr.register(FakeSocket(), user_b)
    mgr.subscribe(conn_a, uuid4())  # different conversations
    mgr.subscribe(conn_b, uuid4())
    await mgr.revoke_pair(user_a, user_b, {'code': 'forbidden'}, conversation_ids=[])
    assert len(conn_a.subscriptions) == 1  # untouched
    assert len(conn_b.subscriptions) == 1
    await mgr.unregister(conn_a)
    await mgr.unregister(conn_b)
