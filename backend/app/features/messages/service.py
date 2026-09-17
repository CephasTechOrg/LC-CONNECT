"""Messages domain logic: access checks, serialization, idempotent write, keyset paging.

`persist_message_idempotent` is the single write path shared by the REST endpoint and
the WebSocket gateway. Paging uses the composite index (conversation_id, created_at, id) —
a keyset scan (O(limit)), never OFFSET.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select, tuple_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.features.messages.schema import (
    GroupThreadInfo,
    MessageRead,
    MessageReadBy,
    MessageThreadRead,
)
from app.models import CampusPosition, Conversation, ConversationMember, Group, Match, Message, Profile, User
from app.shared.policies import open_staff_thread_ids
from app.shared.profiles import profile_load_options
from app.shared.serializers import profile_to_public

_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)

# Conversation kinds that carry a single "partner" (as opposed to a group).
_PARTNER_KINDS = ('dm', 'staff_dm')


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


async def list_threads_for_user(db: AsyncSession, user_id: UUID) -> list[MessageThreadRead]:
    """Unified inbox: every conversation the user is an active member of — DMs *and* groups —
    newest activity first. DM rows carry the partner; group rows carry the group."""
    conversations = (
        await db.execute(
            select(Conversation)
            .join(ConversationMember, ConversationMember.conversation_id == Conversation.id)
            .where(ConversationMember.user_id == user_id, ConversationMember.status == 'active')
        )
    ).scalars().all()
    if not conversations:
        return []

    # A staff thread whose staff side lost their position is no longer accessible — drop it
    # here too, so the inbox never lists a thread that would 403 on open.
    open_staff_ids = await open_staff_thread_ids(db, [c.id for c in conversations if c.kind == 'staff_dm'])
    conversations = [c for c in conversations if c.kind != 'staff_dm' or c.id in open_staff_ids]
    if not conversations:
        return []

    conv_ids = [c.id for c in conversations]
    latest = (
        await db.execute(
            select(Message)
            .where(Message.conversation_id.in_(conv_ids))
            .distinct(Message.conversation_id)
            .order_by(Message.conversation_id, Message.created_at.desc(), Message.id.desc())
        )
    ).scalars().all()
    latest_map = {m.conversation_id: m for m in latest}

    # Partner profiles (the other active member of each DM / staff_dm conversation).
    partner_style_ids = [c.id for c in conversations if c.kind in _PARTNER_KINDS]
    partner_of: dict[UUID, UUID] = {}
    if partner_style_ids:
        for cid, uid in (
            await db.execute(
                select(ConversationMember.conversation_id, ConversationMember.user_id).where(
                    ConversationMember.conversation_id.in_(partner_style_ids),
                    ConversationMember.user_id != user_id,
                )
            )
        ).all():
            partner_of[cid] = uid
    profiles = {
        p.user_id: p
        for p in (
            await db.execute(
                select(Profile).options(*profile_load_options()).where(Profile.user_id.in_(partner_of.values()))
            )
        ).scalars().all()
    } if partner_of else {}
    # Verified campus position, if any — surfaced so a student can see *who* a staff
    # partner is (title/department), not just a name.
    positions = {
        p.user_id: p
        for p in (
            await db.execute(
                select(CampusPosition).where(
                    CampusPosition.user_id.in_(partner_of.values()),
                    CampusPosition.is_primary.is_(True),
                    CampusPosition.is_active.is_(True),
                    CampusPosition.status == 'verified',
                )
            )
        ).scalars().all()
    } if partner_of else {}

    # Group metadata.
    group_ids = [c.id for c in conversations if c.kind == 'group']
    group_of = {
        g.conversation_id: g
        for g in (
            (await db.execute(select(Group).where(Group.conversation_id.in_(group_ids)))).scalars().all()
            if group_ids else []
        )
    }

    threads: list[MessageThreadRead] = []
    for conv in conversations:
        latest_msg = latest_map.get(conv.id)
        if conv.kind in _PARTNER_KINDS:
            partner_profile = profiles.get(partner_of.get(conv.id))
            if partner_profile is None:
                continue  # orphaned conversation (partner profile missing) — skip, as before
            position = positions.get(partner_of.get(conv.id))
            threads.append(MessageThreadRead(
                conversation_id=conv.id, kind=conv.kind, match_id=conv.match_id,
                partner=profile_to_public(partner_profile),
                partner_position_title=position.official_title if position else None,
                partner_department=position.department if position else None,
                latest_message=message_read(latest_msg) if latest_msg else None,
            ))
        else:
            group = group_of.get(conv.id)
            if group is None:
                continue
            threads.append(MessageThreadRead(
                conversation_id=conv.id, kind='group',
                group=GroupThreadInfo(id=group.id, name=group.name, avatar_url=group.avatar_url),
                latest_message=message_read(latest_msg) if latest_msg else None,
            ))

    # Newest activity first; a message beats an empty thread.
    threads.sort(
        key=lambda t: t.latest_message.created_at if t.latest_message else _EPOCH,
        reverse=True,
    )
    return threads


def message_read(message: Message) -> MessageRead:
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
        deleted=deleted,
    )


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
    rows = (
        await db.execute(
            select(User.id, Profile)
            .join(ConversationMember, ConversationMember.user_id == User.id)
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
            .options(*profile_load_options())
        )
    ).all()

    return [
        MessageReadBy(
            user_id=user_id,
            profile=profile_to_public(profile) if profile is not None else None,
        )
        for user_id, profile in rows
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
        # `populate_existing`-style read-back without a second round trip: the INSERT returns the
        # server-generated `created_at`, so the `db.refresh(message)` that used to follow the
        # commit is unnecessary. That refresh was a third round trip on the critical path of every
        # single message, purely to read back one column the INSERT already knew.
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
