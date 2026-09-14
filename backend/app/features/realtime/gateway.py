"""WebSocket gateway: `/api/v1/ws`.

Lifecycle: accept → authenticate (first frame must be `auth`, within a timeout) →
serve (dispatch loop) → unregister. Every inbound frame is size-capped then validated;
every send is re-authorized; one bad frame or handler never tears down the socket.
Idle sockets are closed by the lifespan reaper (`WS_IDLE_TIMEOUT_SECONDS`); dead
transport is also detected by uvicorn ping/pong.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from app.config import settings
from app.database import AsyncSessionLocal
from app.features.messages.service import persist_message_idempotent
from app.features.realtime import protocol, service
from app.features.realtime.manager import Connection
from app.features.realtime.protocol import CloseCode, ErrorCode
from app.features.realtime.runtime import (
    emit_message_created,
    event_bus,
    malformed_limiter,
    manager,
    ping_limiter,
    send_limiter,
    subscribe_limiter,
    typing_limiter,
)
from app.features.realtime.ws_io import FrameTooLarge, receive_json_bounded
from app.shared.conversations import active_member_ids, active_members_with_mute

logger = logging.getLogger('lc_connect.realtime')

router = APIRouter()


@router.websocket('/ws')
async def websocket_gateway(websocket: WebSocket) -> None:
    await websocket.accept()
    conn = await _authenticate(websocket)
    if conn is None:
        return
    try:
        await _serve(websocket, conn)
    finally:
        await manager.unregister(conn)


async def _close(websocket: WebSocket, code: int) -> None:
    with contextlib.suppress(Exception):
        await websocket.close(code)


async def _recv(websocket: WebSocket):
    """Bounded JSON receive shared by auth + serve loops."""
    return await receive_json_bounded(websocket, settings.ws_max_frame_bytes)


# ── authentication ────────────────────────────────────────────────────────────

async def _authenticate(websocket: WebSocket) -> Connection | None:
    try:
        raw = await asyncio.wait_for(_recv(websocket), timeout=settings.ws_auth_timeout_seconds)
    except TimeoutError:
        await _close(websocket, CloseCode.AUTH_TIMEOUT)
        return None
    except WebSocketDisconnect:
        return None
    except FrameTooLarge:
        await _close(websocket, CloseCode.ABUSE)
        return None
    except Exception:
        await _close(websocket, CloseCode.AUTH_FAILED)
        return None

    if not isinstance(raw, dict) or raw.get('type') != 'auth':
        await _close(websocket, CloseCode.AUTH_FAILED)
        return None
    try:
        frame = protocol.AuthFrame.model_validate(raw)
    except ValidationError:
        await _close(websocket, CloseCode.AUTH_FAILED)
        return None

    async with AsyncSessionLocal() as db:
        try:
            user = await service.authenticate(db, frame.access_token)
        except service.WsAuthFailed:
            await _close(websocket, CloseCode.AUTH_FAILED)
            return None
        except service.WsForbidden:
            await _close(websocket, CloseCode.FORBIDDEN)
            return None

    if manager.user_socket_count(user.id) >= settings.ws_max_sockets_per_user:
        await _close(websocket, CloseCode.ABUSE)
        return None

    conn = manager.register(websocket, user.id)
    manager.send(conn, protocol.auth_ok(user.id, settings.ws_heartbeat_seconds))
    return conn


# ── serve loop ────────────────────────────────────────────────────────────────

async def _serve(websocket: WebSocket, conn: Connection) -> None:
    while True:
        try:
            raw = await _recv(websocket)
        except WebSocketDisconnect:
            return
        except FrameTooLarge:
            if not await _tolerate_oversized(websocket, conn):
                return
            continue
        except Exception:
            if not await _tolerate_malformed(websocket, conn):
                return
            continue

        manager.touch(conn)
        try:
            frame = protocol.parse_inbound(raw)
        except ValidationError:
            if not await _tolerate_malformed(websocket, conn):
                return
            continue

        try:
            await _dispatch(conn, frame)
        except Exception:
            manager.send(conn, protocol.error(ErrorCode.INTERNAL, 'Server error'))


async def _tolerate_malformed(websocket: WebSocket, conn: Connection) -> bool:
    """Emit an error for a bad frame; close (return False) once the abuse limit trips."""
    if not malformed_limiter.allow(id(conn)):
        await _close(websocket, CloseCode.ABUSE)
        return False
    manager.send(conn, protocol.error(ErrorCode.INVALID_FRAME, 'Malformed frame'))
    return True


async def _tolerate_oversized(websocket: WebSocket, conn: Connection) -> bool:
    """Oversized frames share the malformed abuse budget — DoS protection, not a soft retry."""
    if not malformed_limiter.allow(id(conn)):
        await _close(websocket, CloseCode.ABUSE)
        return False
    manager.send(
        conn,
        protocol.error(ErrorCode.FRAME_TOO_LARGE, 'Frame exceeds size limit'),
    )
    return True


async def _dispatch(conn: Connection, frame: protocol.InboundFrame) -> None:
    match frame:
        case protocol.SubscribeFrame():
            await _on_subscribe(conn, frame)
        case protocol.UnsubscribeFrame():
            _on_unsubscribe(conn, frame)
        case protocol.SendFrame():
            await _on_send(conn, frame)
        case protocol.TypingStartFrame():
            await _on_typing(conn, frame.conversation_id, active=True)
        case protocol.TypingStopFrame():
            await _on_typing(conn, frame.conversation_id, active=False)
        case protocol.ReadFrame():
            await _on_read(conn, frame)
        case protocol.PingFrame():
            _on_ping(conn)
        case protocol.AuthFrame():
            manager.send(conn, protocol.error(ErrorCode.INVALID_FRAME, 'Already authenticated'))


# ── handlers ──────────────────────────────────────────────────────────────────

async def _on_subscribe(conn: Connection, frame: protocol.SubscribeFrame) -> None:
    if not subscribe_limiter.allow(id(conn)):
        manager.send(conn, protocol.error(ErrorCode.RATE_LIMITED, 'Too many subscriptions', frame.request_id))
        return
    async with AsyncSessionLocal() as db:
        try:
            await service.recheck_account(db, conn.user_id)
            conversation = await service.authorize_conversation(db, conn.user_id, frame.conversation_id)
            others = await active_member_ids(db, conversation.id, exclude=conn.user_id)
        except service.WsForbidden:
            manager.send(conn, protocol.error(ErrorCode.FORBIDDEN, 'Forbidden', frame.request_id))
            return
    # Cache the other members so typing needs no per-keystroke DB hit. One for a DM, N-1 for
    # a group — typing fans out to all of them. Keyed canonically, like the manager index.
    conn.partners[conversation.id] = others
    conn.addressing[conversation.id] = str(conversation.match_id or conversation.id)
    manager.subscribe(conn, conversation.id, ref=frame.conversation_id)
    # The ack echoes the client's own ref — that is what it correlates the subscription on.
    manager.send(conn, protocol.subscribed(frame.request_id, frame.conversation_id))


def _on_ping(conn: Connection) -> None:
    """Keepalive. `manager.touch` already ran in the serve loop before dispatch, so the idle
    clock is refreshed even when the reply is throttled.

    Over budget we drop silently instead of returning an error frame: an error would let a ping
    flood amplify outbound traffic, and clients treat error frames as send failures.
    """
    if not ping_limiter.allow(id(conn)):
        return
    manager.send(conn, protocol.pong())


def _on_unsubscribe(conn: Connection, frame: protocol.UnsubscribeFrame) -> None:
    manager.unsubscribe(conn, frame.conversation_id)
    manager.send(conn, protocol.unsubscribed(frame.conversation_id))


async def _on_send(conn: Connection, frame: protocol.SendFrame) -> None:
    if not await send_limiter.aallow((conn.user_id, frame.conversation_id)):
        manager.send(conn, protocol.error(ErrorCode.RATE_LIMITED, 'Slow down', frame.request_id))
        return
    async with AsyncSessionLocal() as db:
        try:
            await service.recheck_account(db, conn.user_id)
            conversation = await service.authorize_conversation(db, conn.user_id, frame.conversation_id)
            # (user_id, muted) for every other active member — live to all, push skips muted.
            recipients = await active_members_with_mute(db, conversation.id, exclude=conn.user_id)
        except service.WsForbidden:
            manager.send(conn, protocol.error(ErrorCode.FORBIDDEN, 'Forbidden', frame.request_id))
            return
        message, created = await persist_message_idempotent(
            db,
            sender_id=conn.user_id,
            match_id=conversation.match_id,
            conversation_id=conversation.id,
            body=frame.body,
            client_message_id=frame.client_message_id,
        )
    manager.send(conn, protocol.message_ack(frame.request_id, message, duplicate=not created))
    if created:
        await emit_message_created(
            message,
            sender_id=conn.user_id,
            recipients=recipients,
        )


async def _on_typing(conn: Connection, conversation_id: UUID, active: bool) -> None:
    # Authz proxy: members are cached only for authorized subscriptions (and cleared on
    # block/suspension/removal revocation), so this avoids a DB hit per keystroke while safe.
    canonical = conn.canonical(conversation_id)
    partners = conn.partners.get(canonical)
    if not partners:
        return
    if active and not await typing_limiter.aallow((conn.user_id, canonical)):
        return
    # Deliver to every other member's USER channel → shows inside the chat and on their list.
    # One recipient for a DM, all others for a group. The frame carries the *addressing* id,
    # which is what the recipient's open chat matches on.
    frame = protocol.typing_event(conn.addressing.get(canonical, str(conversation_id)), conn.user_id, active)
    for partner_id in partners:
        await event_bus.publish_to_user(partner_id, frame)


async def _on_read(conn: Connection, frame: protocol.ReadFrame) -> None:
    async with AsyncSessionLocal() as db:
        try:
            await service.recheck_account(db, conn.user_id)
            conversation = await service.authorize_conversation(db, conn.user_id, frame.conversation_id)
        except service.WsForbidden:
            return
        read_at = await service.mark_read(
            db,
            reader_id=conn.user_id,
            match_id=frame.conversation_id,
            through_message_id=frame.through_message_id,
        )
    if read_at is None:
        return
    # Route on the canonical id (what the manager indexes), but address the frame with the
    # client-facing id (what the recipient's open chat matches on). Before subscriptions were
    # canonicalised these were the same value for a DM, which is why this read correctly by
    # accident — it must not go back to echoing the client's ref.
    await event_bus.publish_to_conversation(
        conversation.id,
        protocol.read_receipt(
            conversation.match_id or conversation.id,
            conn.user_id,
            frame.through_message_id,
            read_at.isoformat(),
        ),
        exclude_user=conn.user_id,
    )
