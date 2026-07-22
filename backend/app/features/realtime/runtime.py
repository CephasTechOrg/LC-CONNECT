"""Process-wide realtime singletons + revocation helpers.

Lives in its own module so REST features (safety/admin) can trigger live revocation
without importing the gateway (which would create an import cycle).
"""

from __future__ import annotations

from uuid import UUID

from app.config import settings
from app.features.realtime import protocol
from app.features.realtime.event_bus import InMemoryEventBus
from app.features.realtime.manager import ConnectionManager
from app.features.realtime.rate_limit import RateLimiter

manager = ConnectionManager(outbox_max=settings.ws_outbox_max_size)
event_bus = InMemoryEventBus(manager)

# 10-second windows for message/typing/subscribe; a 60s window for malformed frames.
send_limiter = RateLimiter(settings.ws_send_rate_per_10s, 10)
typing_limiter = RateLimiter(settings.ws_typing_rate_per_10s, 10)
subscribe_limiter = RateLimiter(settings.ws_subscribe_rate_per_10s, 10)
malformed_limiter = RateLimiter(settings.ws_max_malformed_frames, 60)


async def revoke_pair_access(user_a: UUID, user_b: UUID) -> None:
    """A block happened — drop any live conversation the two users share."""
    frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Conversation access revoked')
    await manager.revoke_pair(user_a, user_b, frame)


async def disconnect_user(user_id: UUID) -> None:
    """A suspension happened — close every socket for the user."""
    frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Account suspended')
    await manager.close_user(user_id, frame, protocol.CloseCode.FORBIDDEN)
