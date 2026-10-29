"""Live presence: tell a user's DM partners when they come online and go offline.

"Online" is "has a live socket on this instance". A transition is detected from socket counts
around register/unregister, so it costs nothing per heartbeat:

- **First socket** (0 → 1): if an offline announcement is pending (a quick reconnect after a
  network switch or app resume), cancel it and say nothing — the partner never saw them go.
  Otherwise announce "online" and record last-seen (throttled).
- **Last socket gone** (1 → 0): wait `presence_offline_grace_seconds`; if still gone, record
  last-seen and announce "offline, last seen at …".

Known limit, shared with `schedule_offline_push`: with several API instances, socket counts are
per instance. A Redis key would be the fix if the API ever scales out.
"""

from __future__ import annotations

import asyncio
import logging
import time
from datetime import UTC, datetime
from uuid import UUID

from app.config import settings
from app.database import AsyncSessionLocal
from app.features.realtime import protocol
from app.features.realtime import runtime as rt
from app.shared.presence import presence_audience, record_last_seen

logger = logging.getLogger('lc_connect.realtime')

_pending_offline: dict[UUID, asyncio.Task] = {}
_last_write: dict[UUID, float] = {}


async def on_connect(user_id: UUID) -> None:
    """Call after the socket is registered."""
    if rt.manager.user_socket_count(user_id) != 1:
        return
    pending = _pending_offline.pop(user_id, None)
    if pending is not None and not pending.done():
        pending.cancel()
        return  # back within the grace window — partners never saw them leave
    now = datetime.now(UTC)
    await _publish(user_id, protocol.presence(user_id, online=True, last_seen_at=None))
    if time.monotonic() - _last_write.get(user_id, -1e9) >= settings.presence_last_seen_write_throttle_seconds:
        await _write_last_seen(user_id, now)


def on_disconnect(user_id: UUID) -> None:
    """Call after the socket is unregistered."""
    if rt.manager.user_socket_count(user_id) != 0 or user_id in _pending_offline:
        return
    task = asyncio.create_task(_go_offline_after_grace(user_id))
    _pending_offline[user_id] = task
    task.add_done_callback(lambda t: _pending_offline.pop(user_id, None) if _pending_offline.get(user_id) is t else None)


async def _go_offline_after_grace(user_id: UUID) -> None:
    await asyncio.sleep(settings.presence_offline_grace_seconds)
    if rt.manager.user_socket_count(user_id) != 0:
        return
    now = datetime.now(UTC)
    await _write_last_seen(user_id, now)
    await _publish(user_id, protocol.presence(user_id, online=False, last_seen_at=now.isoformat()))


async def on_visibility_changed(user_id: UUID, *, visible: bool, audience_before: list[UUID]) -> None:
    """The user turned "Show online status" off or on. Turning it off tells the people who could
    see it to hide it now; turning it on announces the current state to the new audience."""
    if not visible:
        frame = protocol.presence(user_id, online=False, last_seen_at=None, visible=False)
        for partner in audience_before:
            await _send(partner, frame)
        return
    online = rt.manager.user_socket_count(user_id) > 0
    await _publish(user_id, protocol.presence(user_id, online=online, last_seen_at=None))


async def _write_last_seen(user_id: UUID, at: datetime) -> None:
    _last_write[user_id] = time.monotonic()
    try:
        async with AsyncSessionLocal() as db:
            await record_last_seen(db, user_id, at)
    except Exception as exc:  # noqa: BLE001 — presence must never break a connection
        logger.warning('record_last_seen failed (user=%s): %s', user_id, exc)


async def _publish(user_id: UUID, frame: dict) -> None:
    try:
        async with AsyncSessionLocal() as db:
            audience = await presence_audience(db, user_id)
    except Exception as exc:  # noqa: BLE001
        logger.warning('presence_audience failed (user=%s): %s', user_id, exc)
        return
    for partner in audience:
        await _send(partner, frame)


async def _send(user_id: UUID, frame: dict) -> None:
    try:
        await rt.event_bus.publish_to_user(user_id, frame)
    except Exception as exc:  # noqa: BLE001
        logger.warning('presence publish failed (user=%s): %s', user_id, exc)
