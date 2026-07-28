"""Conversation resolution + membership (P2 of the groups plan).

Messaging internals key on a **conversation**; DMs are still *addressed* externally by
`match_id` during the transition, so this module is the translation layer:

- `ensure_dm_conversation` — get-or-create a match's conversation + its two members
  (idempotent, and a safety net for any match created outside the P1 backfill);
- `active_member_ids` / `is_active_member` — membership works identically for a 2-person DM
  and an N-person group, which is the whole point of the generalization.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.models import Conversation, ConversationMember, Match
from app.shared.policies import staff_thread_is_open, users_are_blocked

ACTIVE = 'active'

# Conversation kinds where a mutual block should close the thread for both sides (unlike a
# group, which has moderators and can't be "blocked" as a pair).
_BLOCKABLE_KINDS = ('dm', 'staff_dm')


async def _dm_conversation(db: AsyncSession, match_id: UUID) -> Conversation | None:
    return (
        await db.execute(select(Conversation).where(Conversation.match_id == match_id))
    ).scalar_one_or_none()


async def ensure_dm_conversation(db: AsyncSession, match: Match) -> Conversation:
    """The DM conversation for `match`, creating it (and both members) if absent.

    Race-safe: `Conversation.match_id` is UNIQUE, so two concurrent creators can't both
    succeed — the loser catches the IntegrityError and reloads the winner's row (the same
    arbiter pattern as message idempotency). A match therefore never gains a second
    conversation.
    """
    existing = await _dm_conversation(db, match.id)
    if existing is not None:
        return existing

    conversation = Conversation(kind='dm', match_id=match.id)
    db.add(conversation)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        winner = await _dm_conversation(db, match.id)
        if winner is None:  # pragma: no cover — the unique violation guarantees a row exists
            raise
        return winner

    for user_id in (match.user_a_id, match.user_b_id):
        db.add(
            ConversationMember(
                conversation_id=conversation.id, user_id=user_id, role='member', status=ACTIVE
            )
        )
    await db.flush()
    return conversation


async def find_staff_dm(db: AsyncSession, user_a: UUID, user_b: UUID) -> Conversation | None:
    """The existing `staff_dm` conversation between exactly these two users, if any."""
    member_a = aliased(ConversationMember)
    member_b = aliased(ConversationMember)
    return (
        await db.execute(
            select(Conversation)
            .join(member_a, member_a.conversation_id == Conversation.id)
            .join(member_b, member_b.conversation_id == Conversation.id)
            .where(
                Conversation.kind == 'staff_dm',
                member_a.user_id == user_a,
                member_a.status == ACTIVE,
                member_b.user_id == user_b,
                member_b.status == ACTIVE,
            )
        )
    ).scalars().first()


async def ensure_staff_dm_conversation(db: AsyncSession, user_a: UUID, user_b: UUID) -> Conversation:
    """Get-or-create the `staff_dm` conversation between two users.

    Unlike `ensure_dm_conversation`, there is no `Match` to key uniqueness off of — a
    `staff_dm` is addressed directly by its own conversation id (the same pattern a group
    uses). Creation is a rare, human-initiated action (not a swipe-matching hot path), so a
    plain check-then-create is an acceptable trade-off over adding pair-uniqueness plumbing
    for a single low-contention feature.
    """
    existing = await find_staff_dm(db, user_a, user_b)
    if existing is not None:
        return existing

    conversation = Conversation(kind='staff_dm')
    db.add(conversation)
    await db.flush()
    for user_id in (user_a, user_b):
        db.add(ConversationMember(conversation_id=conversation.id, user_id=user_id, role='member', status=ACTIVE))
    await db.flush()
    return conversation


async def conversation_for_match_id(db: AsyncSession, match_id: UUID) -> Conversation | None:
    """Resolve a match id to its conversation, provisioning one if it's missing."""
    match = await db.get(Match, match_id)
    if match is None:
        return None
    return await ensure_dm_conversation(db, match)


async def resolve_conversation(db: AsyncSession, ref: UUID) -> Conversation | None:
    """Resolve a client-supplied id to a conversation.

    `ref` may be a **conversation id** (groups address their chat directly) or a **match id**
    (DMs are still addressed by match during the transition). Tries the conversation table
    first, then falls back to the match → DM-conversation path.
    """
    conversation = await db.get(Conversation, ref)
    if conversation is not None:
        return conversation
    return await conversation_for_match_id(db, ref)


async def accessible_conversation(db: AsyncSession, ref: UUID, user_id: UUID) -> Conversation:
    """Resolve `ref` (match id or conversation id) and confirm the user may use it, for the
    REST message endpoints. 404 if it doesn't exist or they're not an active member; 403 if a
    DM is blocked. Mirrors the WebSocket `authorize_conversation`, but with HTTP errors."""
    conversation = await resolve_conversation(db, ref)
    if conversation is None or not await is_active_member(db, conversation.id, user_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Conversation not found')
    if conversation.kind in _BLOCKABLE_KINDS:
        for other_id in await active_member_ids(db, conversation.id, exclude=user_id):
            if await users_are_blocked(db, user_id, other_id):
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Messaging is blocked')
    # A staff thread closes once the staff side is no longer official (position revoked).
    if conversation.kind == 'staff_dm' and not await staff_thread_is_open(db, conversation.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail='This staff conversation is no longer available'
        )
    return conversation


async def active_members_with_mute(
    db: AsyncSession, conversation_id: UUID, *, exclude: UUID | None = None
) -> list[tuple[UUID, bool]]:
    """Active members as `(user_id, muted)`. Live delivery goes to all of them; push skips the
    muted ones."""
    stmt = select(ConversationMember.user_id, ConversationMember.muted).where(
        ConversationMember.conversation_id == conversation_id,
        ConversationMember.status == 'active',
    )
    if exclude is not None:
        stmt = stmt.where(ConversationMember.user_id != exclude)
    return [(user_id, muted) for user_id, muted in (await db.execute(stmt)).all()]


async def addressing_ids_for_conversations(
    db: AsyncSession, conversation_ids: list[UUID]
) -> dict[UUID, UUID]:
    """conversation_id → the id clients address it by: the DM's match id, or (for a group) the
    conversation id itself. Used to key unread counts consistently across DMs and groups."""
    if not conversation_ids:
        return {}
    rows = (
        await db.execute(
            select(Conversation.id, Conversation.match_id).where(Conversation.id.in_(conversation_ids))
        )
    ).all()
    return {conversation_id: (match_id or conversation_id) for conversation_id, match_id in rows}


async def member_role(db: AsyncSession, conversation_id: UUID, user_id: UUID) -> str | None:
    """The user's role in a conversation if they're an active member, else None. DM members are
    always 'member', so an `admin`/`owner` result only ever comes from a group."""
    return (
        await db.execute(
            select(ConversationMember.role).where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
                ConversationMember.status == ACTIVE,
            )
        )
    ).scalar_one_or_none()


async def is_active_member(db: AsyncSession, conversation_id: UUID, user_id: UUID) -> bool:
    return (
        await db.execute(
            select(ConversationMember.id).where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
                ConversationMember.status == ACTIVE,
            )
        )
    ).scalar_one_or_none() is not None


async def active_member_ids(
    db: AsyncSession, conversation_id: UUID, *, exclude: UUID | None = None
) -> list[UUID]:
    """Active members of a conversation. For a DM with `exclude=me` this is "the partner";
    for a group it is the fan-out audience."""
    stmt = select(ConversationMember.user_id).where(
        ConversationMember.conversation_id == conversation_id,
        ConversationMember.status == ACTIVE,
    )
    if exclude is not None:
        stmt = stmt.where(ConversationMember.user_id != exclude)
    return list((await db.execute(stmt)).scalars().all())
