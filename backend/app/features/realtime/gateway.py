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
    event_bus,
    malformed_limiter,
    manager,
    schedule_offline_push,
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
    # a group — typing fans out to all of them.
    conn.partners[frame.conversation_id] = others
    manager.subscribe(conn, frame.conversation_id)
    manager.send(conn, protocol.subscribed(frame.request_id, frame.conversation_id))


def _on_unsubscribe(conn: Connection, frame: protocol.UnsubscribeFrame) -> None:
    manager.unsubscribe(conn, frame.conversation_id)
    manager.send(conn, protocol.unsubscribed(frame.conversation_id))


async def _on_send(conn: Connection, frame: protocol.SendFrame) -> None:
    if not send_limiter.allow((conn.user_id, frame.conversation_id)):
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
        # Conversation channel: live message stream to subscribers (they dedupe against
        # the ack by client_message_id — the canonical merge behavior).
        await event_bus.publish_to_conversation(frame.conversation_id, protocol.message_created(message))
        # User channels: thread-list update for both participants (regardless of open chat).
        updated = protocol.conversation_updated(message)
        await event_bus.publish_to_user(conn.user_id, updated)
        for recipient_id, muted in recipients:
            await event_bus.publish_to_user(recipient_id, updated)  # live to all (even muted)
            # Offline push: only for members who are muted-off and have no live socket.
            open_sockets = manager.user_socket_count(recipient_id)
            if muted or open_sockets != 0:
                continue
            logger.info('send: recipient=%s offline+unmuted -> scheduling offline push', recipient_id)
            if open_sockets == 0:
                asyncio.create_task(
                    schedule_offline_push(recipient_id, conn.user_id, frame.conversation_id)
                )


async def _on_typing(conn: Connection, conversation_id: UUID, active: bool) -> None:
    # Authz proxy: members are cached only for authorized subscriptions (and cleared on
    # block/suspension/removal revocation), so this avoids a DB hit per keystroke while safe.
    partners = conn.partners.get(conversation_id)
    if not partners:
        return
    if active and not typing_limiter.allow((conn.user_id, conversation_id)):
        return
    # Deliver to every other member's USER channel → shows inside the chat and on their list.
    # One recipient for a DM, all others for a group.
    frame = protocol.typing_event(conversation_id, conn.user_id, active)
    for partner_id in partners:
        await event_bus.publish_to_user(partner_id, frame)


async def _on_read(conn: Connection, frame: protocol.ReadFrame) -> None:
    async with AsyncSessionLocal() as db:
        try:
            await service.authorize_conversation(db, conn.user_id, frame.conversation_id)
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
    await event_bus.publish_to_conversation(
        frame.conversation_id,
        protocol.read_receipt(frame.conversation_id, conn.user_id, frame.through_message_id, read_at.isoformat()),
        exclude_user=conn.user_id,
    )
