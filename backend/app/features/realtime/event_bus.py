"""EventBus seam — decouples the gateway from *how* events fan out.

``InMemoryEventBus``: single-instance (publish == local deliver).
``RedisEventBus``: publish to env-prefixed Pub/Sub; a subscriber task on every
API process delivers only to that process's local sockets.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Protocol
from uuid import UUID

from app.features.realtime.manager import ConnectionManager
from app.shared.redis_client import get_redis

logger = logging.getLogger('lc_connect.realtime')


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

    async def publish_to_user(self, user_id: UUID, frame: dict[str, Any]) -> None: ...

    async def publish_control(self, payload: dict[str, Any]) -> None: ...


class InMemoryEventBus:
    """Single-instance bus: publish == deliver to this instance's local sockets."""

    def __init__(self, manager: ConnectionManager) -> None:
        self._manager = manager

    async def publish_to_conversation(
        self, conversation_id: UUID, frame: dict[str, Any], exclude_user: UUID | None = None
    ) -> None:
        await self._manager.deliver_to_conversation(conversation_id, frame, exclude_user)

    async def publish_to_user(self, user_id: UUID, frame: dict[str, Any]) -> None:
        self._manager.deliver_to_user(user_id, frame)

    async def publish_control(self, payload: dict[str, Any]) -> None:
        await apply_control_event(self._manager, payload)


class RedisEventBus:
    """Cross-instance fan-out via Redis Pub/Sub.

    When the shared client is unavailable (not connected yet / outage), falls back to
    local delivery so a single healthy instance still serves its own sockets.
    """

    def __init__(self, manager: ConnectionManager, env_slug: str) -> None:
        self._manager = manager
        self._env = env_slug

    async def publish_to_conversation(
        self, conversation_id: UUID, frame: dict[str, Any], exclude_user: UUID | None = None
    ) -> None:
        envelope = {
            'kind': 'conversation',
            'conversation_id': str(conversation_id),
            'exclude_user': str(exclude_user) if exclude_user else None,
            'frame': frame,
        }
        if not await self._publish(conversation_channel(self._env, conversation_id), envelope):
            await self._manager.deliver_to_conversation(conversation_id, frame, exclude_user)

    async def publish_to_user(self, user_id: UUID, frame: dict[str, Any]) -> None:
        envelope = {
            'kind': 'user',
            'user_id': str(user_id),
            'frame': frame,
        }
        if not await self._publish(user_channel(self._env, user_id), envelope):
            self._manager.deliver_to_user(user_id, frame)

    async def publish_control(self, payload: dict[str, Any]) -> None:
        envelope = {'kind': 'control', **payload}
        if not await self._publish(control_channel(self._env), envelope):
            await apply_control_event(self._manager, payload)

    async def _publish(self, channel: str, envelope: dict[str, Any]) -> bool:
        client = get_redis()
        if client is None:
            return False
        try:
            await client.publish(channel, json.dumps(envelope, default=str))
            return True
        except Exception:  # noqa: BLE001 — degrade to local delivery
            logger.warning('redis publish failed (%s) — local fallback', channel, exc_info=True)
            return False

    async def run_subscriber(self) -> None:
        """Block forever: pattern-subscribe and deliver to local sockets.

        Cancelled by lifespan on shutdown. Reconnects with backoff on errors.
        """
        import asyncio

        patterns = [
            f'lcconnect:{self._env}:conversation:*',
            f'lcconnect:{self._env}:user:*',
            f'lcconnect:{self._env}:control',
        ]
        backoff = 1.0
        while True:
            client = get_redis()
            if client is None:
                await asyncio.sleep(1.0)
                continue
            pubsub = client.pubsub()
            try:
                await pubsub.psubscribe(*patterns)
                logger.info('redis subscriber: listening on %s', patterns)
                backoff = 1.0
                async for message in pubsub.listen():
                    if message.get('type') not in {'pmessage', 'message'}:
                        continue
                    data = message.get('data')
                    if not isinstance(data, str):
                        continue
                    await self._handle_raw(data)
            except asyncio.CancelledError:
                await pubsub.aclose()
                raise
            except Exception:  # noqa: BLE001
                logger.warning('redis subscriber error — retry in %.1fs', backoff, exc_info=True)
                try:
                    await pubsub.aclose()
                except Exception:  # noqa: BLE001
                    pass
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 30.0)

    async def _handle_raw(self, raw: str) -> None:
        try:
            envelope = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning('redis fan-out: bad JSON')
            return
        kind = envelope.get('kind')
        if kind == 'conversation':
            conversation_id = UUID(envelope['conversation_id'])
            exclude = envelope.get('exclude_user')
            exclude_user = UUID(exclude) if exclude else None
            await self._manager.deliver_to_conversation(
                conversation_id, envelope['frame'], exclude_user
            )
        elif kind == 'user':
            self._manager.deliver_to_user(UUID(envelope['user_id']), envelope['frame'])
        elif kind == 'control':
            await apply_control_event(self._manager, envelope)
        else:
            logger.warning('redis fan-out: unknown kind=%s', kind)


async def apply_control_event(manager: ConnectionManager, payload: dict[str, Any]) -> None:
    """Apply a control envelope on this instance's local sockets (block / suspend / announce)."""
    from app.features.realtime import protocol

    event = payload.get('event')
    if event == 'user.suspended':
        user_id = UUID(payload['user_id'])
        frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Account suspended')
        await manager.close_user(user_id, frame, protocol.CloseCode.FORBIDDEN)
    elif event == 'pair.revoked':
        frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Conversation access revoked')
        raw_ids = payload.get('conversation_ids') or []
        conversation_ids = [UUID(value) for value in raw_ids]
        if conversation_ids:
            await manager.revoke_pair(
                UUID(payload['user_a']),
                UUID(payload['user_b']),
                frame,
                conversation_ids=conversation_ids,
            )
    elif event == 'member.revoked':
        frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Removed from conversation')
        await manager.revoke_member(
            UUID(payload['conversation_id']),
            UUID(payload['user_id']),
            frame,
        )
    elif event == 'conversation.revoked':
        frame = protocol.error(protocol.ErrorCode.FORBIDDEN, 'Conversation access revoked')
        await manager.revoke_conversation(UUID(payload['conversation_id']), frame)
    elif event == 'announcement':
        manager.broadcast(protocol.announcement_event(payload['audience']))
    else:
        logger.warning('redis control: unknown event=%s', event)
