"""In-memory connection manager for the WebSocket gateway (single instance).

Data structures (all O(1) add/remove/lookup, event-loop-atomic — no locks needed):

    _by_user:         user_id         -> set[Connection]    # fan-out to a user's devices
    _by_conversation: conversation_id -> set[Connection]    # fan-out to subscribers

Each Connection has a bounded outbox drained by its own writer task, so one slow or
dead socket can never block a broadcast (it is dropped on overflow/error instead).
Delivery only ever *enqueues* (O(1) per socket); it never awaits a socket inline.
"""

from __future__ import annotations

import asyncio
import contextlib
import time
from typing import Any, Protocol
from uuid import UUID

_SHUTDOWN = object()


class SocketLike(Protocol):
    async def send_json(self, data: Any) -> None: ...
    async def close(self, code: int = 1000) -> None: ...


class Connection:
    """A single authenticated socket and its outbound pipeline."""

    __slots__ = ('socket', 'user_id', 'subscriptions', 'partners', 'last_seen', 'alive', '_outbox', '_writer')

    def __init__(self, socket: SocketLike, user_id: UUID, outbox_max: int) -> None:
        self.socket = socket
        self.user_id = user_id
        self.subscriptions: set[UUID] = set()
        # conversation_id -> other active member ids, cached at subscribe so typing needs no DB
        # hit. One entry for a DM, N-1 for a group.
        self.partners: dict[UUID, list[UUID]] = {}
        self.last_seen: float = time.monotonic()
        self.alive: bool = True
        self._outbox: asyncio.Queue[Any] = asyncio.Queue(maxsize=outbox_max)
        self._writer: asyncio.Task[None] | None = None

    def start(self) -> None:
        self._writer = asyncio.create_task(self._run())

    async def _run(self) -> None:
        try:
            while True:
                frame = await self._outbox.get()
                if frame is _SHUTDOWN:
                    return
                await self.socket.send_json(frame)
        except Exception:
            # Socket is dead; the gateway's receive loop will unregister us.
            self.alive = False

    def enqueue(self, frame: dict[str, Any]) -> bool:
        """Non-blocking. Returns False if the socket is dead or its outbox is full."""
        if not self.alive:
            return False
        try:
            self._outbox.put_nowait(frame)
            return True
        except asyncio.QueueFull:
            self.alive = False  # slow consumer — isolate + drop
            return False

    async def stop(self, code: int = 1000) -> None:
        self.alive = False
        with contextlib.suppress(asyncio.QueueFull):
            self._outbox.put_nowait(_SHUTDOWN)
        if self._writer is not None:
            self._writer.cancel()
            with contextlib.suppress(BaseException):
                await self._writer
        with contextlib.suppress(Exception):
            await self.socket.close(code)


class ConnectionManager:
    def __init__(self, outbox_max: int = 256) -> None:
        self._outbox_max = outbox_max
        self._by_user: dict[UUID, set[Connection]] = {}
        self._by_conversation: dict[UUID, set[Connection]] = {}

    # ── registration ──────────────────────────────────────────────────────────

    def user_socket_count(self, user_id: UUID) -> int:
        return len(self._by_user.get(user_id, ()))

    def register(self, socket: SocketLike, user_id: UUID) -> Connection:
        conn = Connection(socket, user_id, self._outbox_max)
        self._by_user.setdefault(user_id, set()).add(conn)
        conn.start()
        return conn

    async def unregister(self, conn: Connection, code: int = 1000) -> None:
        """Idempotent: remove from all indices and tear down the socket."""
        for conv_id in list(conn.subscriptions):
            self._detach_conversation(conn, conv_id)
        conn.subscriptions.clear()
        peers = self._by_user.get(conn.user_id)
        if peers is not None:
            peers.discard(conn)
            if not peers:
                del self._by_user[conn.user_id]
        await conn.stop(code)

    # ── subscriptions ─────────────────────────────────────────────────────────

    def subscribe(self, conn: Connection, conversation_id: UUID) -> None:
        conn.subscriptions.add(conversation_id)
        self._by_conversation.setdefault(conversation_id, set()).add(conn)

    def unsubscribe(self, conn: Connection, conversation_id: UUID) -> None:
        conn.subscriptions.discard(conversation_id)
        conn.partners.pop(conversation_id, None)
        self._detach_conversation(conn, conversation_id)

    def _detach_conversation(self, conn: Connection, conversation_id: UUID) -> None:
        subs = self._by_conversation.get(conversation_id)
        if subs is not None:
            subs.discard(conn)
            if not subs:
                del self._by_conversation[conversation_id]

    # ── delivery ──────────────────────────────────────────────────────────────

    def send(self, conn: Connection, frame: dict[str, Any]) -> bool:
        return conn.enqueue(frame)

    def deliver_to_user(self, user_id: UUID, frame: dict[str, Any]) -> int:
        """Enqueue `frame` to every socket a user has open (their user channel).

        Used for conversation-list updates that must reach a user regardless of
        which conversation they currently have open. O(devices).
        """
        conns = self._by_user.get(user_id)
        if not conns:
            return 0
        return sum(1 for conn in tuple(conns) if conn.enqueue(frame))

    async def deliver_to_conversation(
        self,
        conversation_id: UUID,
        frame: dict[str, Any],
        exclude_user: UUID | None = None,
    ) -> int:
        """Enqueue `frame` to every subscribed socket (optionally excluding a user).

        Returns the number of sockets reached. Dead/overflowed sockets are reaped
        after the fan-out (never mutating the set mid-iteration).
        """
        subs = self._by_conversation.get(conversation_id)
        if not subs:
            return 0
        reached = 0
        dead: list[Connection] = []
        for conn in tuple(subs):
            if exclude_user is not None and conn.user_id == exclude_user:
                continue
            if conn.enqueue(frame):
                reached += 1
            else:
                dead.append(conn)
        for conn in dead:
            await self.unregister(conn)
        return reached

    # ── revocation (block / suspension) ───────────────────────────────────────

    async def revoke_conversation(self, conversation_id: UUID, frame: dict[str, Any]) -> None:
        """Notify + unsubscribe every socket from a conversation (e.g. on block)."""
        subs = self._by_conversation.get(conversation_id)
        if not subs:
            return
        for conn in tuple(subs):
            conn.enqueue(frame)
            self.unsubscribe(conn, conversation_id)

    async def revoke_member(self, conversation_id: UUID, user_id: UUID, frame: dict[str, Any]) -> None:
        """Unsubscribe a single user from a conversation (e.g. removed/banned from a group).
        Their other conversations are untouched."""
        subs = self._by_conversation.get(conversation_id)
        if not subs:
            return
        for conn in tuple(subs):
            if conn.user_id == user_id:
                conn.enqueue(frame)
                self.unsubscribe(conn, conversation_id)

    async def revoke_pair(self, user_a: UUID, user_b: UUID, frame: dict[str, Any]) -> None:
        """Revoke conversations both users are actively subscribed to (a block).

        No DB/match lookup needed: a conversation is a match between exactly two
        users, so any conversation both currently subscribe to is theirs.
        """
        convs_a = {cid for conn in self._by_user.get(user_a, ()) for cid in conn.subscriptions}
        if not convs_a:
            return
        convs_b = {cid for conn in self._by_user.get(user_b, ()) for cid in conn.subscriptions}
        for conversation_id in convs_a & convs_b:
            await self.revoke_conversation(conversation_id, frame)

    async def close_user(self, user_id: UUID, frame: dict[str, Any], code: int) -> None:
        """Close every socket for a user (e.g. on suspension)."""
        conns = self._by_user.get(user_id)
        if not conns:
            return
        for conn in tuple(conns):
            conn.enqueue(frame)
            await self.unregister(conn, code)

    # ── heartbeat / shutdown ──────────────────────────────────────────────────

    def touch(self, conn: Connection) -> None:
        conn.last_seen = time.monotonic()

    async def reap_idle(self, idle_seconds: float, code: int) -> int:
        cutoff = time.monotonic() - idle_seconds
        stale = [c for conns in self._by_user.values() for c in conns if c.last_seen < cutoff]
        for conn in stale:
            conn.enqueue({'type': 'error', 'code': 'idle_timeout', 'message': 'Connection idle'})
            await self.unregister(conn, code)
        return len(stale)

    async def shutdown(self, code: int) -> None:
        for conns in list(self._by_user.values()):
            for conn in tuple(conns):
                await self.unregister(conn, code)

    # ── introspection (tests/metrics) ─────────────────────────────────────────

    @property
    def total_connections(self) -> int:
        return sum(len(conns) for conns in self._by_user.values())

    def conversation_subscriber_count(self, conversation_id: UUID) -> int:
        return len(self._by_conversation.get(conversation_id, ()))
