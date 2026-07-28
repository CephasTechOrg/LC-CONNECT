"""Realtime DB logic: authenticate, authorize, idempotent persist, read receipts.

Every function here is the authority — the gateway never trusts the client. Errors
are raised as `WsAuthFailed`/`WsForbidden` so the gateway can map them to close codes
and *generic* messages (never revealing whether an inaccessible conversation exists).
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Conversation, ConversationMember, Message, User
from app.security import verify_supabase_access_token
from app.shared.conversations import active_member_ids, is_active_member, resolve_conversation
from app.shared.policies import staff_thread_is_open, users_are_blocked

# Kept in sync with `app.shared.conversations._BLOCKABLE_KINDS`.
_BLOCKABLE_KINDS = ('dm', 'staff_dm')


class WsAuthFailed(Exception):
    """Token missing/invalid/expired, or user not yet bootstrapped."""


class WsForbidden(Exception):
    """Account not permitted (inactive/suspended/unverified) or conversation not accessible."""


async def authenticate(db: AsyncSession, token: str) -> User:
    """Verify a Supabase token and resolve the active, verified LC Connect user."""
    try:
        claims = await verify_supabase_access_token(token)
    except ValueError as exc:
        raise WsAuthFailed('Invalid or expired token') from exc

    user = (
        await db.execute(select(User).where(User.auth_user_id == claims.sub))
    ).scalar_one_or_none()
    if user is None:
        raise WsAuthFailed('User not bootstrapped')
    _ensure_account_ok(user)
    return user


async def recheck_account(db: AsyncSession, user_id: UUID) -> User:
    """Re-load and re-validate the account (suspension can happen mid-session)."""
    user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
    if user is None:
        raise WsForbidden('Account not available')
    _ensure_account_ok(user)
    return user


def _ensure_account_ok(user: User) -> None:
    if not user.is_active or user.status != 'active':
        raise WsForbidden('Account inactive or suspended')
    if not user.is_verified:
        raise WsForbidden('Verified account required')


async def authorize_conversation(db: AsyncSession, user_id: UUID, conversation_ref: UUID) -> Conversation:
    """Confirm the user may access the conversation. Generic forbidden on any failure.

    Authorization is **membership-based** (`ConversationMember`), which reads identically for a
    2-person DM and an N-person group. `conversation_ref` is a group's conversation id or a DM's
    match id (resolved here) — so the same gateway path serves both.
    """
    conversation = await resolve_conversation(db, conversation_ref)
    if conversation is None or not await is_active_member(db, conversation.id, user_id):
        raise WsForbidden('Conversation not accessible')

    # DM-only relationship rule: a block closes the conversation for both sides.
    if conversation.kind in _BLOCKABLE_KINDS:
        for other_id in await active_member_ids(db, conversation.id, exclude=user_id):
            if await users_are_blocked(db, user_id, other_id):
                raise WsForbidden('Conversation not accessible')
    # A staff thread closes once the staff side is no longer official (position revoked).
    if conversation.kind == 'staff_dm' and not await staff_thread_is_open(db, conversation.id):
        raise WsForbidden('Conversation not accessible')
    return conversation


async def mark_read(
    db: AsyncSession, *, reader_id: UUID, match_id: UUID, through_message_id: UUID
) -> datetime | None:
    # `match_id` here is really a conversation-ref (DM match id or group conversation id).
    """Advance the reader's boundary to `through_message_id`. Returns the timestamp.

    Two things happen:
    1. `ConversationMember.last_read_message_id` — the **authoritative** unread boundary
       (per-member, so it works for an N-member group). Only ever moves forward.
    2. `Message.read_at` — kept for **DM read receipts** (a single column can't express
       per-member read state, so it is display-only, not the unread source of truth).
    """
    conversation = await resolve_conversation(db, match_id)
    if conversation is None:
        return None

    cursor = (
        await db.execute(
            select(Message.created_at, Message.id).where(
                Message.id == through_message_id, Message.conversation_id == conversation.id
            )
        )
    ).one_or_none()
    if cursor is None:
        return None
    cursor_created, cursor_id = cursor

    now = datetime.now(UTC)

    # 1. Advance the boundary — never backwards (an out-of-order read must not "unread").
    member = (
        await db.execute(
            select(ConversationMember).where(
                ConversationMember.conversation_id == conversation.id,
                ConversationMember.user_id == reader_id,
            )
        )
    ).scalar_one_or_none()
    if member is None:
        return None
    if member.last_read_message_id is None:
        member.last_read_message_id = cursor_id
    else:
        current = (
            await db.execute(
                select(Message.created_at, Message.id).where(Message.id == member.last_read_message_id)
            )
        ).one_or_none()
        if current is None or (current[0], current[1]) < (cursor_created, cursor_id):
            member.last_read_message_id = cursor_id

    # 2. Keep DM receipts working.
    await db.execute(
        update(Message)
        .where(
            Message.conversation_id == conversation.id,
            Message.sender_id != reader_id,
            Message.created_at <= cursor_created,
            Message.read_at.is_(None),
        )
        .values(read_at=now)
    )
    await db.commit()
    return now
