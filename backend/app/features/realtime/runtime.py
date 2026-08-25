"""Process-wide realtime singletons + revocation helpers.

Lives in its own module so REST features (safety/admin) can trigger live revocation
without importing the gateway (which would create an import cycle).
"""

from __future__ import annotations

import asyncio
import logging
from uuid import UUID

from sqlalchemy import select

from app.config import settings
from app.database import AsyncSessionLocal
from app.features.notifications.push import push_sender
from app.features.realtime import protocol
from app.features.realtime.event_bus import InMemoryEventBus
from app.features.realtime.manager import ConnectionManager
from app.models import Conversation, ConversationMember, Profile
from app.shared.rate_limit import RateLimiter

logger = logging.getLogger('lc_connect.realtime')

manager = ConnectionManager(outbox_max=settings.ws_outbox_max_size)
event_bus = InMemoryEventBus(manager)

# 10-second windows for message/typing/subscribe; a 60s window for malformed frames.
send_limiter = RateLimiter(settings.ws_send_rate_per_10s, 10)
typing_limiter = RateLimiter(settings.ws_typing_rate_per_10s, 10)
subscribe_limiter = RateLimiter(settings.ws_subscribe_rate_per_10s, 10)
malformed_limiter = RateLimiter(settings.ws_max_malformed_frames, 60)


async def run_idle_reaper() -> None:
    """Periodically drop sockets that have not received an inbound frame recently.

    Complements uvicorn's ping/pong (transport-alive) with an application-level idle
    timeout (no client frames). Interval is a fraction of the idle timeout so we do
    not wait a full idle window after the cutoff before closing.
    """
    log = logging.getLogger('lc_connect.realtime')
    interval = max(15, settings.ws_idle_timeout_seconds // 3)
    while True:
        await asyncio.sleep(interval)
        try:
            closed = await manager.reap_idle(
                float(settings.ws_idle_timeout_seconds),
                protocol.CloseCode.IDLE_TIMEOUT,
            )
            if closed:
                log.info('idle reaper: closed %d websocket(s)', closed)
        except Exception:  # noqa: BLE001 — housekeeping must never crash the app
            log.warning('idle reaper failed', exc_info=True)


# Deliberately small: only notifications worth a push. Everything else (role changes, removals,
# rejections, ...) stays live-only — the in-app badge catches them up on next open.
PUSHABLE_NOTIFICATION_TYPES = frozenset({
    'connection_request',
    'connection_accepted',
    'group_invite',
    'group_join_request',
    'group_request_approved',
    'program_membership_verified',
    'admin_membership_invited',
})


async def emit_notification(
    *, user_id: UUID, notif_type: str, group_id: UUID | None = None, actor_id: UUID | None = None
) -> None:
    """Persist an in-app notification and deliver it live to the recipient's user channel.

    Best-effort and self-contained (own session): the group action is the source of truth, this
    is a side effect. An offline recipient still gets it — the row persists and their badge seeds
    from `GET /notifications/unread-count` on next open. For the small set of high-value types
    (see `PUSHABLE_NOTIFICATION_TYPES`), a still-offline recipient also gets a push.
    """
    from app.features.notifications import service as notifications_service

    try:
        async with AsyncSessionLocal() as db:
            notification = await notifications_service.create_notification(
                db, user_id=user_id, type=notif_type, group_id=group_id, actor_id=actor_id
            )
            await db.commit()
            await db.refresh(notification)
            dto = await notifications_service.read_one(db, notification)
        await event_bus.publish_to_user(user_id, protocol.notification_event(dto.model_dump(mode='json')))
        if notif_type in PUSHABLE_NOTIFICATION_TYPES and push_sender.enabled:
            actor_name = dto.actor.display_name if dto.actor else None
            group_name = dto.group.name if dto.group else None
            asyncio.create_task(_schedule_notification_push(user_id, notif_type, actor_name, group_name))
    except Exception as exc:  # noqa: BLE001 - a notification must never break the triggering action
        logger.warning('emit_notification failed (type=%s user=%s): %s', notif_type, user_id, exc)


async def _schedule_notification_push(
    user_id: UUID, notif_type: str, actor_name: str | None, group_name: str | None
) -> None:
    """Push only if the recipient is *still* offline after a short grace window — mirrors the
    message-push grace (absorbs Wi-Fi↔cellular handoffs); they already got it live otherwise."""
    await asyncio.sleep(settings.push_reconnect_grace_seconds)
    if manager.user_socket_count(user_id) != 0:
        return  # reconnected during the grace window — they'll see it live
    async with AsyncSessionLocal() as db:
        await push_sender.notify_in_app_event(
            db, recipient_id=user_id, notif_type=notif_type, actor_name=actor_name, group_name=group_name,
        )


async def broadcast_announcement(audience: str) -> None:
    """Ping every connected client that a new announcement is live, so their unread counter can
    tick up in real time. Best-effort and content-free — the client filters by its own role."""
    try:
        manager.broadcast(protocol.announcement_event(audience))
    except Exception as exc:  # noqa: BLE001 — a live ping must never break publishing
        logger.warning('broadcast_announcement failed (audience=%s): %s', audience, exc)


async def broadcast_message_deleted(conversation_id: UUID, message_id: UUID, member_ids: list[UUID]) -> None:
    """Tell every conversation member (via their user channel) that a message was deleted, so an
    open chat tombstones it live. Best-effort."""
    frame = protocol.message_deleted(conversation_id, message_id)
    for user_id in member_ids:
        await event_bus.publish_to_user(user_id, frame)


async def revoke_pair_access(user_a: UUID, user_b: UUID) -> None:
    """A block happened — drop any live conversation the two users share."""
    frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Conversation access revoked')
    await manager.revoke_pair(user_a, user_b, frame)


async def disconnect_user(user_id: UUID) -> None:
    """A suspension happened — close every socket for the user."""
    frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Account suspended')
    await manager.close_user(user_id, frame, protocol.CloseCode.FORBIDDEN)


async def revoke_staff_conversations(user_id: UUID) -> None:
    """A staff position was revoked — drop every live `staff_dm` the user is in.

    Authorization is re-checked per frame, so a revoked member can no longer send; this also
    detaches both sides' open subscriptions so an ex-official channel stops streaming.
    Best-effort: the revocation itself is the source of truth.
    """
    try:
        async with AsyncSessionLocal() as db:
            conversation_ids = list(
                (
                    await db.execute(
                        select(Conversation.id)
                        .join(ConversationMember, ConversationMember.conversation_id == Conversation.id)
                        .where(
                            Conversation.kind == 'staff_dm',
                            ConversationMember.user_id == user_id,
                            ConversationMember.status == 'active',
                        )
                    )
                ).scalars().all()
            )
        frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Conversation access revoked')
        for conversation_id in conversation_ids:
            await manager.revoke_conversation(conversation_id, frame)
    except Exception as exc:  # noqa: BLE001 - revocation must never break the admin action
        logger.warning('revoke_staff_conversations failed (user=%s): %s', user_id, exc)


async def schedule_offline_push(recipient_id: UUID, sender_id: UUID, conversation_id: UUID) -> None:
    """Push only if the recipient is *still* offline after a short grace window (rec #1) —
    absorbs Wi-Fi↔cellular handoffs / rapid reconnects. Fire-and-forget from the send path."""
    if not push_sender.enabled:
        return
    await asyncio.sleep(settings.push_reconnect_grace_seconds)
    after_grace = manager.user_socket_count(recipient_id)
    if after_grace != 0:
        logger.info('offline push skipped: recipient=%s reconnected during grace (sockets=%d)', recipient_id, after_grace)
        return  # reconnected during the grace window — they'll get it live
    logger.info('offline push firing: recipient=%s still offline after grace', recipient_id)
    async with AsyncSessionLocal() as db:
        name = (
            await db.execute(select(Profile.display_name).where(Profile.user_id == sender_id))
        ).scalar_one_or_none()
        await push_sender.notify_new_message(
            db,
            recipient_id=recipient_id,
            sender_name=name or 'Someone',
            conversation_id=conversation_id,
            sender_id=sender_id,
        )
