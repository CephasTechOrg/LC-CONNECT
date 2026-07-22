"""EventBus seam — decouples the gateway from *how* events fan out.

`InMemoryEventBus` delivers straight to local sockets (single instance). A future
`RedisEventBus` will publish to the env-prefixed channels below and a subscriber task
will feed `manager.deliver_to_conversation` — same gateway code, no protocol change.
"""

from __future__ import annotations

from typing import Any, Protocol
from uuid import UUID

from app.features.realtime.manager import ConnectionManager


def conversation_channel(env_slug: str, conversation_id: UUID) -> str:
    return f'lcconnect:{env_slug}:conversation:{conversation_id}'


def user_channel(env_slug: str, user_id: UUID) -> str:
    return f'lcconnect:{env_slug}:user:{user_id}'


def control_channel(env_slug: str) -> str:
    return f'lcconnect:{env_slug}:control'


class EventBus(Protocol):
    async def publish_to_conversation(
        self, conversation_id: UUID, frame: dict[str, Any], exclude_user: UUID | None = None
    ) -> None: ...


class InMemoryEventBus:
    """Single-instance bus: publish == deliver to this instance's local sockets."""

    def __init__(self, manager: ConnectionManager) -> None:
        self._manager = manager

    async def publish_to_conversation(
        self, conversation_id: UUID, frame: dict[str, Any], exclude_user: UUID | None = None
    ) -> None:
        await self._manager.deliver_to_conversation(conversation_id, frame, exclude_user)
