"""`GET /messages/threads/{id}/presence` — a DM partner's online state, as the viewer may see it."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import PresenceRead
from app.models import Conversation
from app.shared.conversations import active_member_ids
from app.shared.presence import PRESENCE_KINDS, last_seen_at, shows_presence


async def partner_presence(db: AsyncSession, conversation: Conversation, viewer_id: UUID) -> PresenceRead:
    """The caller has already been authorized for `conversation`. Groups have no presence (a 404,
    as for any thread the route does not apply to)."""
    if conversation.kind not in PRESENCE_KINDS:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No presence for this conversation')
    partners = await active_member_ids(db, conversation.id, exclude=viewer_id)
    if not partners:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No presence for this conversation')
    partner = partners[0]
    visible = await shows_presence(db, viewer_id) and await shows_presence(db, partner)
    if not visible:
        return PresenceRead(user_id=partner, visible=False)

    from app.features.realtime.runtime import manager

    online = manager.user_socket_count(partner) > 0
    return PresenceRead(
        user_id=partner,
        visible=True,
        online=online,
        last_seen_at=None if online else await last_seen_at(db, partner),
    )
