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

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Conversation, ConversationMember, Match

ACTIVE = 'active'


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


async def match_ids_for_conversations(
    db: AsyncSession, conversation_ids: list[UUID]
) -> dict[UUID, UUID]:
    """conversation_id → match_id, for translating internal ids back to the ids clients
    currently use. Transitional: group conversations have no match and are simply absent."""
    if not conversation_ids:
        return {}
    rows = (
        await db.execute(
            select(Conversation.id, Conversation.match_id).where(
                Conversation.id.in_(conversation_ids), Conversation.match_id.is_not(None)
            )
        )
    ).all()
    return {conversation_id: match_id for conversation_id, match_id in rows}


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
