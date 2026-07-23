"""WebSocket gateway: `/api/v1/ws`.

Lifecycle: accept → authenticate (first frame must be `auth`, within a timeout) →
serve (dispatch loop) → unregister. Every inbound frame is validated; every send is
re-authorized; one bad frame or handler never tears down the socket. Dead sockets are
detected by uvicorn ping/pong and the receive loop's disconnect.
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
from app.shared.conversations import active_member_ids

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


# ── authentication ────────────────────────────────────────────────────────────

async def _authenticate(websocket: WebSocket) -> Connection | None:
    try:
        raw = await asyncio.wait_for(websocket.receive_json(), timeout=settings.ws_auth_timeout_seconds)
    except TimeoutError:
        await _close(websocket, CloseCode.AUTH_TIMEOUT)
        return None
    except WebSocketDisconnect:
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
            raw = await websocket.receive_json()
        except WebSocketDisconnect:
            return
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
    # Cache the partner so typing needs no per-keystroke DB hit. (DM = exactly one other
    # member; groups will fan out to `others` instead.)
    if others:
        conn.partners[frame.conversation_id] = others[0]
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
            recipients = await active_member_ids(db, conversation.id, exclude=conn.user_id)
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
        for recipient_id in recipients:
            await event_bus.publish_to_user(recipient_id, updated)
            # Offline push: if this member has no live socket, notify after a grace recheck.
            open_sockets = manager.user_socket_count(recipient_id)
            logger.info(
                'send: recipient=%s open_sockets=%d -> %s',
                recipient_id,
                open_sockets,
                'scheduling offline push' if open_sockets == 0 else 'recipient online, delivered live (no push)',
            )
            if open_sockets == 0:
                asyncio.create_task(
                    schedule_offline_push(recipient_id, conn.user_id, frame.conversation_id)
                )


async def _on_typing(conn: Connection, conversation_id: UUID, active: bool) -> None:
    # Authz proxy: the partner is cached only for authorized subscriptions (and cleared on
    # block/suspension revocation), so this avoids a DB hit per keystroke while staying safe.
    partner_id = conn.partners.get(conversation_id)
    if partner_id is None:
        return
    if active and not typing_limiter.allow((conn.user_id, conversation_id)):
        return
    # Deliver to the partner's USER channel → shows both inside the chat and on their
    # conversation list (1:1, so the partner is the only other participant).
    await event_bus.publish_to_user(
        partner_id,
        protocol.typing_event(conversation_id, conn.user_id, active),
    )


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
