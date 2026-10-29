"""Messages domain logic: access checks, serialization, idempotent write, keyset paging.

`persist_message_idempotent` is the single write path shared by the REST endpoint and
the WebSocket gateway. Paging uses the composite index (conversation_id, created_at, id) —
a keyset scan (O(limit)), never OFFSET.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import and_, func, or_, select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.features.messages.schema import (
    MessageRead,
    MessageReadBy,
    ReactionSummary,
    ReplyPreview,
)
from app.models import (
    Conversation,
    ConversationMember,
    Match,
    Message,
    Profile,
    User,
)


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
            .join(Conversation, Conversation.id == ConversationMember.conversation_id)
            .outerjoin(boundary, boundary.id == ConversationMember.last_read_message_id)
            .where(
                ConversationMember.user_id == user_id,
                ConversationMember.status == 'active',
                Message.sender_id != user_id,
                # A deleted message is a tombstone with nothing to read; counting it left a badge
                # the user could never clear by reading.
                Message.deleted_at.is_(None),
                or_(
                    # No boundary yet: in a group, only what arrived since joining — someone added
                    # to a busy group used to start with its entire history unread. A DM's members
                    # can postdate its messages (chats carried over from before conversations
                    # existed), so there everything still counts.
                    and_(
                        ConversationMember.last_read_message_id.is_(None),
                        or_(Conversation.kind != 'group', Message.created_at >= ConversationMember.joined_at),
                    ),
                    tuple_(Message.created_at, Message.id) > tuple_(boundary.created_at, boundary.id),
                ),
            )
            .group_by(ConversationMember.conversation_id)
        )
    ).all()
    per_conversation = {conversation_id: count for conversation_id, count in rows}
    return sum(per_conversation.values()), per_conversation


def message_read(
    message: Message,
    *,
    delivered: bool = False,
    reactions: list[ReactionSummary] | None = None,
    reply: ReplyPreview | None = None,
) -> MessageRead:
    deleted = message.deleted_at is not None
    return MessageRead(
        id=message.id,
        match_id=message.match_id,  # None for group messages
        conversation_id=message.conversation_id,
        sender_id=message.sender_id,
        client_message_id=message.client_message_id,
        body='' if deleted else message.body,  # never leak the original body of a deleted message
        created_at=message.created_at,
        read_at=message.read_at,
        delivered=delivered,
        deleted=deleted,
        edited_at=message.edited_at,
        reactions=reactions or [],
        reply_to=reply,
    )


async def delivery_cursor(
    db: AsyncSession, conversation_id: UUID, *, exclude: UUID
) -> tuple[datetime, UUID] | None:
    """The `(created_at, id)` every *other* member has acknowledged receipt through, or None.

    The minimum across members, so in a group it means "everyone has it" — and for a DM, where
    there is one other member, it is simply that member's boundary. That is the only definition
    the sender's tick can honestly carry.

    Exists because the delivered tick was otherwise **not durable**: the boundary is persisted
    per member, but nothing returned it, so the state lived only in the live `messages.delivery`
    frame. Every page load, app restart and cache miss silently dropped every second tick back to
    one — which reads as "the message never arrived".

    One query per page, not per message. With the API and the database in different regions a
    per-message check over a 50-row page would be ~3 seconds.
    """
    boundary = aliased(Message)
    rows = (
        await db.execute(
            select(boundary.created_at, boundary.id)
            .select_from(ConversationMember)
            .outerjoin(boundary, boundary.id == ConversationMember.last_delivered_message_id)
            .where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.status == 'active',
                ConversationMember.user_id != exclude,
            )
        )
    ).all()
    if not rows:
        return None
    # A member who has acknowledged nothing (NULL boundary) holds the minimum at "nothing", so
    # one silent member means nothing is reported delivered. That is the correct reading of
    # "everyone has it", and it is why a group — whose acknowledgements are deliberately not
    # collected at all — reports nothing rather than something misleading.
    if any(created_at is None for created_at, _ in rows):
        return None
    return min(rows)



async def read_by(db: AsyncSession, message_id: UUID, actor_id: UUID) -> list[MessageReadBy]:
    """Members whose read boundary has passed `message_id`.

    This is the group answer to report #21. A group cannot show a delivered or read *tick*: doing
    so needs a rule about which members count ("all" or "any"), and the client would have to hold
    every member's boundary to evaluate it — real state for a glyph nobody asked for. A list of
    who has actually read it is both cheaper and more informative, and it is the affordance mature
    messengers offer.

    Excludes the actor. You have read your own message by definition, and listing yourself makes
    a two-person list look like three.

    One query, not one per member: the boundary is a message id, so answering "is this member past
    that message" needs the boundary row's `(created_at, id)`, which is a join rather than a loop.
    With the API and database in different regions a per-member round trip would cost ~60ms each.
    """
    message = (
        await db.execute(
            select(Message.conversation_id, Message.created_at, Message.id).where(
                Message.id == message_id
            )
        )
    ).one_or_none()
    if message is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')
    conversation_id, created_at, ident = message

    # Local import, as in `delete_message` below — a module-level one closes a load cycle with
    # `app.shared.conversations`.
    from app.shared.conversations import accessible_conversation

    # Same gate as every other REST message endpoint: 404 if not a member, 403 if blocked or the
    # staff thread has closed. Without it this would leak group membership to a non-member holding
    # a message id.
    await accessible_conversation(db, conversation_id, actor_id)

    boundary = aliased(Message)
    # Two columns, not a whole profile. `profile_to_public` would have needed
    # `profile_load_options()` — four `selectinload` queries per reader — to serialize bio,
    # interests, languages and a staff contact email that this list never shows.
    rows = (
        await db.execute(
            select(User.id, Profile.display_name, Profile.avatar_url)
            .select_from(ConversationMember)
            .join(User, User.id == ConversationMember.user_id)
            .join(boundary, boundary.id == ConversationMember.last_read_message_id)
            .outerjoin(Profile, Profile.user_id == User.id)
            .where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.status == 'active',
                ConversationMember.user_id != actor_id,
                # The boundary is at or past this message. Compared as a tuple for the same reason
                # the write side does: `created_at` is not unique, because a group fan-out commits
                # many rows in one transaction.
                tuple_(boundary.created_at, boundary.id) >= (created_at, ident),
            )
        )
    ).all()

    return [
        MessageReadBy(user_id=user_id, display_name=display_name, avatar_url=avatar_url)
        for user_id, display_name, avatar_url in rows
    ]



async def delete_message(db: AsyncSession, message_id: UUID, actor_id: UUID) -> Message:
    """Soft-delete a message for everyone. The sender may delete their own message anywhere; a
    group admin/owner may delete any message in their group (moderation). Idempotent."""
    from app.shared.conversations import is_active_member, member_role

    message = await db.get(Message, message_id)
    if message is None or message.conversation_id is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')
    if not await is_active_member(db, message.conversation_id, actor_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')
    if message.sender_id != actor_id:
        if await member_role(db, message.conversation_id, actor_id) not in ('admin', 'owner'):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='You can only delete your own messages')
    if message.deleted_at is None:
        message.deleted_at = datetime.now(UTC)
        await db.commit()
        await db.refresh(message)
    return message


async def persist_message_idempotent(
    db: AsyncSession,
    *,
    sender_id: UUID,
    match_id: UUID,
    conversation_id: UUID,
    body: str,
    client_message_id: UUID | None,
    reply_to_id: UUID | None = None,
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
        reply_to_id=reply_to_id,
    )
    try:
        # A savepoint, so a duplicate rolls back only this insert: a full rollback discarded the
        # caller's other work and expired every object loaded in the session.
        async with db.begin_nested():
            db.add(message)
            # The INSERT returns the server-generated `created_at` (eager defaults), so no
            # `db.refresh(message)` round trip follows the commit.
            await db.flush()
    except IntegrityError:
        if client_message_id is None:
            raise  # not the idempotency key — a real constraint failure, not a retry
        existing = (
            await db.execute(
                select(Message).where(
                    Message.sender_id == sender_id,
                    Message.client_message_id == client_message_id,
                )
            )
        ).scalar_one_or_none()
        if existing is None:
            raise
        if existing.conversation_id != conversation_id:
            # The same client id reused in another chat is a client bug, not a retry; answering
            # with that other chat's message would leak it into this one.
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail='client_message_id already used'
            ) from None
        return existing, False

    await db.commit()
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
