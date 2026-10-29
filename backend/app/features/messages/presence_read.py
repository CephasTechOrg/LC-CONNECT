"""Presence as a viewer may see it: one DM partner (`GET /messages/threads/{id}/presence`), many
people at once (`GET /messages/presence`), and the inbox's online dots."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import PresenceRead
from app.models import Conversation
from app.shared.conversations import active_member_ids
from app.shared.presence import PRESENCE_KINDS, last_seen_many, presence_audience


def _online(user_id: UUID) -> bool:
    from app.features.realtime.runtime import manager

    return manager.user_socket_count(user_id) > 0


async def presence_for_users(db: AsyncSession, viewer_id: UUID, user_ids: list[UUID]) -> list[PresenceRead]:
    """One row per requested person, `visible` false for anyone the viewer may not see — a
    connection or staff partner who shows theirs, while the viewer shows theirs, neither blocked."""
    allowed = set(await presence_audience(db, viewer_id))
    visible = [uid for uid in user_ids if uid in allowed]
    online = {uid for uid in visible if _online(uid)}
    seen = await last_seen_many(db, [uid for uid in visible if uid not in online])
    return [
        PresenceRead(
            user_id=uid,
            visible=uid in allowed,
            online=uid in online,
            last_seen_at=seen.get(uid) if uid in allowed and uid not in online else None,
        )
        for uid in user_ids
    ]


async def online_partners(db: AsyncSession, viewer_id: UUID) -> set[UUID]:
    """The people the viewer may see who are online right now — the inbox's green dots."""
    return {uid for uid in await presence_audience(db, viewer_id) if _online(uid)}


async def partner_presence(db: AsyncSession, conversation: Conversation, viewer_id: UUID) -> PresenceRead:
    """The caller has already been authorized for `conversation`. Groups have no presence (a 404,
    as for any thread the route does not apply to)."""
    if conversation.kind not in PRESENCE_KINDS:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No presence for this conversation')
    partners = await active_member_ids(db, conversation.id, exclude=viewer_id)
    if not partners:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No presence for this conversation')
    return (await presence_for_users(db, viewer_id, [partners[0]]))[0]
