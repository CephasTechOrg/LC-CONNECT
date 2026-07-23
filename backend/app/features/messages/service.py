"""Messages domain logic: access checks, serialization, idempotent write, keyset paging.

`persist_message_idempotent` is the single write path shared by the REST endpoint and
the WebSocket gateway. Paging uses the composite index (conversation_id, created_at, id) —
a keyset scan (O(limit)), never OFFSET.
"""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.features.messages.schema import MessageRead
from app.models import ConversationMember, Match, Message, User


async def get_match_for_user(db: AsyncSession, match_id: UUID, user: User) -> Match:
    match = await db.get(Match, match_id)
    if match is None or user.id not in {match.user_a_id, match.user_b_id}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Match not found')
    return match


def partner_id(match: Match, user: User) -> UUID:
    return match.user_b_id if match.user_a_id == user.id else match.user_a_id


async def unread_summary(db: AsyncSession, user_id: UUID) -> tuple[int, dict[UUID, int]]:
    """Unread counts for the user, in one grouped query (no N+1). Keyed by **conversation id**.

    A message is unread *by this user* when it is in a conversation they're an active member
    of, was sent by someone else, and falls **after their read boundary**
    (`ConversationMember.last_read_message_id`, compared on the keyset `(created_at, id)`).

    The boundary — rather than the per-message `read_at` — is what makes this work for an
    N-member group: a single `read_at` column cannot express *which* member has read a
    message. `read_at` is still maintained for DM read receipts.
    """
    boundary = aliased(Message)  # the member's last-read message, if any
    rows = (
        await db.execute(
            select(ConversationMember.conversation_id, func.count(Message.id))
            .select_from(ConversationMember)
            .join(Message, Message.conversation_id == ConversationMember.conversation_id)
            .outerjoin(boundary, boundary.id == ConversationMember.last_read_message_id)
            .where(
                ConversationMember.user_id == user_id,
                ConversationMember.status == 'active',
                Message.sender_id != user_id,
                or_(
                    ConversationMember.last_read_message_id.is_(None),
                    tuple_(Message.created_at, Message.id) > tuple_(boundary.created_at, boundary.id),
                ),
            )
            .group_by(ConversationMember.conversation_id)
        )
    ).all()
    per_conversation = {conversation_id: count for conversation_id, count in rows}
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
    conversation_id: UUID,
    body: str,
    client_message_id: UUID | None,
) -> tuple[Message, bool]:
    """Insert a message; returns (message, created).

    With a client_message_id the write is idempotent on (sender_id, client_message_id):
    a retry returns the original row (created=False), so acks converge to one server id.
    Race-safe — the partial-unique index is the arbiter; the loser catches IntegrityError.
    Without one (legacy REST), it is a plain insert.
    """
    # Dual-write during the transition: `conversation_id` is the new container, while
    # `match_id` stays populated so the old path remains readable and rollback is trivial.
    message = Message(
        sender_id=sender_id,
        match_id=match_id,
        conversation_id=conversation_id,
        client_message_id=client_message_id,
        body=body,
    )
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
    conversation_id: UUID,
    *,
    before_created_at: datetime | None,
    before_id: UUID | None,
    limit: int,
) -> list[Message]:
    """Newest-first page. `before_*` is the keyset cursor (the oldest row already seen)."""
    stmt = select(Message).where(Message.conversation_id == conversation_id)
    if before_created_at is not None and before_id is not None:
        stmt = stmt.where(tuple_(Message.created_at, Message.id) < tuple_(before_created_at, before_id))
    stmt = stmt.order_by(Message.created_at.desc(), Message.id.desc()).limit(limit)
    return list((await db.execute(stmt)).scalars().all())


async def sync_thread(
    db: AsyncSession,
    conversation_id: UUID,
    *,
    after_created_at: datetime,
    after_id: UUID,
    limit: int,
) -> list[Message]:
    """Oldest-first messages strictly after a cursor — reconnect catch-up."""
    stmt = (
        select(Message)
        .where(
            Message.conversation_id == conversation_id,
            tuple_(Message.created_at, Message.id) > tuple_(after_created_at, after_id),
        )
        .order_by(Message.created_at.asc(), Message.id.asc())
        .limit(limit)
    )
    return list((await db.execute(stmt)).scalars().all())
