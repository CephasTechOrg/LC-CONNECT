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

from app.models import Match, Message, User
from app.security import verify_supabase_access_token
from app.shared.policies import users_are_blocked


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
        raise WsForbidden('Verified student required')


async def authorize_conversation(db: AsyncSession, user_id: UUID, match_id: UUID) -> Match:
    """Confirm the user may access the conversation. Generic forbidden on any failure."""
    match = await db.get(Match, match_id)
    if match is None or user_id not in {match.user_a_id, match.user_b_id}:
        raise WsForbidden('Conversation not accessible')
    partner_id = match.user_b_id if match.user_a_id == user_id else match.user_a_id
    if await users_are_blocked(db, user_id, partner_id):
        raise WsForbidden('Conversation not accessible')
    return match


async def mark_read(
    db: AsyncSession, *, reader_id: UUID, match_id: UUID, through_message_id: UUID
) -> datetime | None:
    """Mark the partner's messages read up to `through_message_id`. Returns the timestamp."""
    cursor_created = (
        await db.execute(
            select(Message.created_at).where(
                Message.id == through_message_id, Message.match_id == match_id
            )
        )
    ).scalar_one_or_none()
    if cursor_created is None:
        return None

    now = datetime.now(UTC)
    await db.execute(
        update(Message)
        .where(
            Message.match_id == match_id,
            Message.sender_id != reader_id,
            Message.created_at <= cursor_created,
            Message.read_at.is_(None),
        )
        .values(read_at=now)
    )
    await db.commit()
    return now
