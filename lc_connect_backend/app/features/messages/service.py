"""Messages domain logic: match access checks and message serialization."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import MessageRead
from app.models import Match, Message, User


async def get_match_for_user(db: AsyncSession, match_id: UUID, user: User) -> Match:
    match = await db.get(Match, match_id)
    if match is None or user.id not in {match.user_a_id, match.user_b_id}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Match not found')
    return match


def partner_id(match: Match, user: User) -> UUID:
    return match.user_b_id if match.user_a_id == user.id else match.user_a_id


def message_read(message: Message) -> MessageRead:
    return MessageRead(id=message.id, match_id=message.match_id, sender_id=message.sender_id, body=message.body, created_at=message.created_at, read_at=message.read_at)
