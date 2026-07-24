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
from app.features.realtime.rate_limit import RateLimiter
from app.models import Profile

logger = logging.getLogger('lc_connect.realtime')

manager = ConnectionManager(outbox_max=settings.ws_outbox_max_size)
event_bus = InMemoryEventBus(manager)

# 10-second windows for message/typing/subscribe; a 60s window for malformed frames.
send_limiter = RateLimiter(settings.ws_send_rate_per_10s, 10)
typing_limiter = RateLimiter(settings.ws_typing_rate_per_10s, 10)
subscribe_limiter = RateLimiter(settings.ws_subscribe_rate_per_10s, 10)
malformed_limiter = RateLimiter(settings.ws_max_malformed_frames, 60)


async def emit_notification(
    *, user_id: UUID, notif_type: str, group_id: UUID | None = None, actor_id: UUID | None = None
) -> None:
    """Persist an in-app notification and deliver it live to the recipient's user channel.

    Best-effort and self-contained (own session): the group action is the source of truth, this
    is a side effect. An offline recipient still gets it — the row persists and their badge seeds
    from `GET /notifications/unread-count` on next open.
    """
    from app.features.notifications import service as notifications_service

    async with AsyncSessionLocal() as db:
        notification = await notifications_service.create_notification(
            db, user_id=user_id, type=notif_type, group_id=group_id, actor_id=actor_id
        )
        await db.commit()
        await db.refresh(notification)
        dto = await notifications_service.read_one(db, notification)
    await event_bus.publish_to_user(user_id, protocol.notification_event(dto.model_dump(mode='json')))


async def revoke_pair_access(user_a: UUID, user_b: UUID) -> None:
    """A block happened — drop any live conversation the two users share."""
    frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Conversation access revoked')
    await manager.revoke_pair(user_a, user_b, frame)


async def disconnect_user(user_id: UUID) -> None:
    """A suspension happened — close every socket for the user."""
    frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Account suspended')
    await manager.close_user(user_id, frame, protocol.CloseCode.FORBIDDEN)


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
