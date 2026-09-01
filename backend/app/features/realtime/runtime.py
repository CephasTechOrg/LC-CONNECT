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
from app.features.realtime.event_bus import InMemoryEventBus, RedisEventBus
from app.features.realtime.manager import ConnectionManager
from app.models import Conversation, ConversationMember, Message, Profile
from app.shared.conversations import blockable_conversation_ids_between
from app.shared.rate_limit import RateLimiter
from app.shared.redis_client import get_redis, redis_configured

logger = logging.getLogger('lc_connect.realtime')

manager = ConnectionManager(outbox_max=settings.ws_outbox_max_size)


class _EventBusProxy:
    """Stable import target — lifespan swaps ``_inner`` to Redis without rebinding callers."""

    def __init__(self) -> None:
        self._inner: InMemoryEventBus | RedisEventBus = InMemoryEventBus(manager)

    async def publish_to_conversation(
        self, conversation_id: UUID, frame: dict, exclude_user: UUID | None = None
    ) -> None:
        await self._inner.publish_to_conversation(conversation_id, frame, exclude_user)

    async def publish_to_user(self, user_id: UUID, frame: dict) -> None:
        await self._inner.publish_to_user(user_id, frame)

    async def publish_control(self, payload: dict) -> None:
        await self._inner.publish_control(payload)


event_bus = _EventBusProxy()

# Conn-id keys stay process-local (``allow``). User/conversation keys use ``aallow``.
send_limiter = RateLimiter(settings.ws_send_rate_per_10s, 10, name='ws_send')
typing_limiter = RateLimiter(settings.ws_typing_rate_per_10s, 10, name='ws_typing')
subscribe_limiter = RateLimiter(settings.ws_subscribe_rate_per_10s, 10, name='ws_subscribe')
malformed_limiter = RateLimiter(settings.ws_max_malformed_frames, 60, name='ws_malformed')


def use_redis_event_bus() -> RedisEventBus | None:
    """Swap proxy inner to Redis fan-out when a client is connected."""
    if not redis_configured() or get_redis() is None:
        return None
    if isinstance(event_bus._inner, RedisEventBus):
        return event_bus._inner
    bus = RedisEventBus(manager, settings.environment_slug)
    event_bus._inner = bus
    logger.info('realtime: RedisEventBus active (env=%s)', settings.environment_slug)
    return bus

async def run_idle_reaper() -> None:
    """Periodically drop sockets that have not received an inbound frame recently."""
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
    """Persist an in-app notification and deliver it live to the recipient's user channel."""
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
    await asyncio.sleep(settings.push_reconnect_grace_seconds)
    if manager.user_socket_count(user_id) != 0:
        return
    async with AsyncSessionLocal() as db:
        await push_sender.notify_in_app_event(
            db, recipient_id=user_id, notif_type=notif_type, actor_name=actor_name, group_name=group_name,
        )


async def broadcast_announcement(audience: str) -> None:
    """Ping connected clients that a new announcement is live (cross-instance via control)."""
    try:
        await event_bus.publish_control({'event': 'announcement', 'audience': audience})
    except Exception as exc:  # noqa: BLE001 — a live ping must never break publishing
        logger.warning('broadcast_announcement failed (audience=%s): %s', audience, exc)


async def emit_message_created(
    message: Message,
    *,
    sender_id: UUID,
    recipients: list[tuple[UUID, bool]],
) -> None:
    """Fan out a persisted message to live subscribers — shared by WS and REST send paths."""
    await event_bus.publish_to_conversation(message.conversation_id, protocol.message_created(message))
    updated = protocol.conversation_updated(message)
    await event_bus.publish_to_user(sender_id, updated)
    for recipient_id, muted in recipients:
        await event_bus.publish_to_user(recipient_id, updated)
        if muted or manager.user_socket_count(recipient_id) != 0:
            continue
        asyncio.create_task(
            schedule_offline_push(recipient_id, sender_id, message.conversation_id)
        )


async def broadcast_message_deleted(conversation_id: UUID, message_id: UUID, member_ids: list[UUID]) -> None:
    frame = protocol.message_deleted(conversation_id, message_id)
    await event_bus.publish_to_conversation(conversation_id, frame)
    for user_id in member_ids:
        await event_bus.publish_to_user(user_id, frame)


async def revoke_pair_access(user_a: UUID, user_b: UUID) -> None:
    """A block happened — drop only dm/staff_dm threads on every instance (never shared groups)."""
    try:
        async with AsyncSessionLocal() as db:
            conversation_ids = await blockable_conversation_ids_between(db, user_a, user_b)
        for conversation_id in conversation_ids:
            await event_bus.publish_control({
                'event': 'conversation.revoked',
                'conversation_id': str(conversation_id),
            })
    except Exception as exc:  # noqa: BLE001 — revocation must never break the block action
        logger.warning('revoke_pair_access failed (%s, %s): %s', user_a, user_b, exc)


async def revoke_member_from_conversation(conversation_id: UUID, user_id: UUID) -> None:
    """A member was removed/banned — drop their live subscription on every instance."""
    await event_bus.publish_control({
        'event': 'member.revoked',
        'conversation_id': str(conversation_id),
        'user_id': str(user_id),
    })


async def disconnect_user(user_id: UUID) -> None:
    """A suspension happened — close every socket for the user on every instance."""
    await event_bus.publish_control({
        'event': 'user.suspended',
        'user_id': str(user_id),
    })


async def revoke_staff_conversations(user_id: UUID) -> None:
    """A staff position was revoked — drop every live `staff_dm` the user is in."""
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
        for conversation_id in conversation_ids:
            await event_bus.publish_control({
                'event': 'conversation.revoked',
                'conversation_id': str(conversation_id),
            })
    except Exception as exc:  # noqa: BLE001 - revocation must never break the admin action
        logger.warning('revoke_staff_conversations failed (user=%s): %s', user_id, exc)


async def schedule_offline_push(recipient_id: UUID, sender_id: UUID, conversation_id: UUID) -> None:
    """Push only if the recipient is still offline on *this* instance after grace.

    Cross-instance presence is not tracked here yet — a user connected only on another
    instance may still get a push (harmless; they already have the live message).
    """
    if not push_sender.enabled:
        return
    await asyncio.sleep(settings.push_reconnect_grace_seconds)
    after_grace = manager.user_socket_count(recipient_id)
    if after_grace != 0:
        logger.info(
            'offline push skipped: recipient=%s reconnected during grace (sockets=%d)',
            recipient_id,
            after_grace,
        )
        return
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
