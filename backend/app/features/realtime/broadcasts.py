"""User-channel broadcasts added for protocol 5: reaction state, notification retraction and
read sync, and mute sync. A module of its own so `runtime.py` stays a readable size.

Reads `runtime.event_bus` through the module attribute rather than importing the name, so tests
that patch the runtime's bus patch these too. Best-effort like every broadcast: a frame that fails
to send is logged, never raised into the action that triggered it.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

from app.database import AsyncSessionLocal
from app.features.realtime import protocol
from app.features.realtime import runtime as rt

logger = logging.getLogger('lc_connect.realtime')


async def broadcast_reaction_change(
    *,
    addressing_id: UUID,
    message_id: UUID,
    actor_id: UUID,
    actor_name: str | None,
    previous: str | None,
    current: str | None,
    counts: list[dict],
    message_sender_id: UUID | None,
    message_snippet: str,
    member_ids: list[UUID],
) -> None:
    """Tell every member — on their user channel, so the inbox hears it with the chat closed, and
    so the actor's own other devices update too — what one person's reaction now is.

    A replace (👍 → ❤️) is sent as a remove of the old emoji then an add of the new. Both frames
    carry the same final state, so a v5 client applying state is unaffected by seeing two, and an
    older client applying each as a +1/−1 still ends with the right counts.
    """
    reacted_at = datetime.now(UTC).isoformat()

    def frame(emoji: str, added: bool) -> dict:
        return protocol.reaction_change(
            conversation_id=addressing_id,
            message_id=message_id,
            user_id=actor_id,
            emoji=emoji,
            added=added,
            user_emoji=current,
            reactions=counts,
            actor_name=actor_name,
            message_sender_id=message_sender_id,
            message_snippet=message_snippet,
            reacted_at=reacted_at,
        )

    frames = []
    if previous is not None:
        frames.append(frame(previous, added=False))
    if current is not None:
        frames.append(frame(current, added=True))
    try:
        for member_id in member_ids:
            for f in frames:
                await rt.event_bus.publish_to_user(member_id, f)
    except Exception as exc:  # noqa: BLE001 — a live update must never break the reaction
        logger.warning('broadcast_reaction_change failed (message=%s): %s', message_id, exc)


async def retract_notification(
    *, user_id: UUID, notif_type: str, actor_id: UUID, subject_id: UUID
) -> None:
    """Withdraw `user_id`'s **unread** notification for this event and tell their devices."""
    from app.features.notifications import service as notifications_service

    try:
        async with AsyncSessionLocal() as db:
            ids = await notifications_service.retract_unread(
                db, user_id=user_id, type=notif_type, actor_id=actor_id, subject_id=subject_id
            )
            await db.commit()
        for notification_id in ids:
            await rt.event_bus.publish_to_user(user_id, protocol.notification_retracted(notification_id))
    except Exception as exc:  # noqa: BLE001
        logger.warning('retract_notification failed (user=%s): %s', user_id, exc)


async def publish_notifications_read(user_id: UUID, notification_ids: list[UUID]) -> None:
    """Tell a user's devices these notifications were read elsewhere."""
    if not notification_ids:
        return
    try:
        await rt.event_bus.publish_to_user(user_id, protocol.notifications_read(notification_ids))
    except Exception as exc:  # noqa: BLE001
        logger.warning('publish_notifications_read failed (user=%s): %s', user_id, exc)


async def broadcast_conversation_muted(user_id: UUID, addressing_id: UUID, muted: bool) -> None:
    """Keep a user's other devices' inbox bell in step with a mute change."""
    try:
        await rt.event_bus.publish_to_user(user_id, protocol.conversation_muted(addressing_id, muted))
    except Exception as exc:  # noqa: BLE001
        logger.warning('broadcast_conversation_muted failed (user=%s): %s', user_id, exc)


async def broadcast_conversation_state(
    user_id: UUID, addressing_id: UUID, *, pinned_at: str | None, archived: bool
) -> None:
    """Keep a user's other devices' inbox arrangement (pins, archive) in step."""
    try:
        await rt.event_bus.publish_to_user(
            user_id, protocol.conversation_state(addressing_id, pinned_at=pinned_at, archived=archived)
        )
    except Exception as exc:  # noqa: BLE001 — a sync frame must never fail the request
        logger.warning('broadcast_conversation_state failed (user=%s): %s', user_id, exc)
