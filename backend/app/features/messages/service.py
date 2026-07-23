"""Messages domain logic: access checks, serialization, idempotent write, keyset paging.

`persist_message_idempotent` is the single write path shared by the REST endpoint and
the WebSocket gateway. Paging uses the composite index (match_id, created_at, id) — a
keyset scan (O(limit)), never OFFSET.
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select, tuple_
from sqlalchemy.exc import IntegrityError
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


async def unread_summary(db: AsyncSession, user_id: UUID) -> tuple[int, dict[UUID, int]]:
    """Unread counts for the user, in one grouped query (no N+1).

    A message is unread *by this user* when it belongs to one of their matches, was sent by
    the partner (``sender_id != user_id``), and has no ``read_at``. Backed by the partial
    index ``ix_messages_unread`` so only unread rows are scanned. Returns
    ``(total, {match_id: count})`` — conversations with zero unread are simply absent.
    """
    rows = (
        await db.execute(
            select(Message.match_id, func.count(Message.id))
            .join(Match, Match.id == Message.match_id)
            .where(
                or_(Match.user_a_id == user_id, Match.user_b_id == user_id),
                Message.sender_id != user_id,
                Message.read_at.is_(None),
            )
            .group_by(Message.match_id)
        )
    ).all()
    per_conversation = {match_id: count for match_id, count in rows}
    return sum(per_conversation.values()), per_conversation


def message_read(message: Message) -> MessageRead:
    return MessageRead(
        id=message.id,
        match_id=message.match_id,
        sender_id=message.sender_id,
        client_message_id=message.client_message_id,
        body=message.body,
        created_at=message.created_at,
        read_at=message.read_at,
    )


async def persist_message_idempotent(
    db: AsyncSession,
    *,
    sender_id: UUID,
    match_id: UUID,
    body: str,
    client_message_id: UUID | None,
) -> tuple[Message, bool]:
    """Insert a message; returns (message, created).

    With a client_message_id the write is idempotent on (sender_id, client_message_id):
    a retry returns the original row (created=False), so acks converge to one server id.
    Race-safe — the partial-unique index is the arbiter; the loser catches IntegrityError.
    Without one (legacy REST), it is a plain insert.
    """
    message = Message(sender_id=sender_id, match_id=match_id, client_message_id=client_message_id, body=body)
    db.add(message)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        existing = (
            await db.execute(
                select(Message).where(
                    Message.sender_id == sender_id,
                    Message.client_message_id == client_message_id,
                )
            )
        ).scalar_one()
        return existing, False

    await db.commit()
    await db.refresh(message)  # populate server-side created_at
    return message, True


async def page_thread(
    db: AsyncSession,
    match_id: UUID,
    *,
    before_created_at: datetime | None,
    before_id: UUID | None,
    limit: int,
) -> list[Message]:
    """Newest-first page. `before_*` is the keyset cursor (the oldest row already seen)."""
    stmt = select(Message).where(Message.match_id == match_id)
    if before_created_at is not None and before_id is not None:
        stmt = stmt.where(tuple_(Message.created_at, Message.id) < tuple_(before_created_at, before_id))
    stmt = stmt.order_by(Message.created_at.desc(), Message.id.desc()).limit(limit)
    return list((await db.execute(stmt)).scalars().all())


async def sync_thread(
    db: AsyncSession,
    match_id: UUID,
    *,
    after_created_at: datetime,
    after_id: UUID,
    limit: int,
) -> list[Message]:
    """Oldest-first messages strictly after a cursor — reconnect catch-up."""
    stmt = (
        select(Message)
        .where(
            Message.match_id == match_id,
            tuple_(Message.created_at, Message.id) > tuple_(after_created_at, after_id),
        )
        .order_by(Message.created_at.asc(), Message.id.asc())
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())
