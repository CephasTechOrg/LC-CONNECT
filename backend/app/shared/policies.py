"""Cross-feature authorization policies.

`users_are_blocked` is a relationship policy used by the connections, messages, and
safety features. Future policies (can_view_profile, can_connect, can_message) belong
here too — see architecture_review/00_current_state_review.md.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Block, Match, Profile, User


async def users_are_blocked(db: AsyncSession, user_a: UUID, user_b: UUID) -> bool:
    result = await db.execute(
        select(Block).where(
            or_(
                (Block.blocker_id == user_a) & (Block.blocked_id == user_b),
                (Block.blocker_id == user_b) & (Block.blocked_id == user_a),
            )
        )
    )
    return result.scalar_one_or_none() is not None


async def users_are_connected(db: AsyncSession, user_a: UUID, user_b: UUID) -> bool:
    """True if the two users share an accepted connection. A `Match` row exists once two
    students connect, so its presence (in either pair order) is the signal — used to gate
    actions that should be limited to people you actually know (e.g. group invites)."""
    result = await db.execute(
        select(Match.id).where(
            or_(
                (Match.user_a_id == user_a) & (Match.user_b_id == user_b),
                (Match.user_a_id == user_b) & (Match.user_b_id == user_a),
            )
        )
    )
    return result.scalar_one_or_none() is not None


async def assert_profile_visible(db: AsyncSession, *, viewer: User, profile: Profile) -> None:
    """Centralized profile-visibility gate. Raise 404 if `viewer` may not see `profile`.

    A profile is hidden from a viewer when it is hidden, when the owner restricts visibility
    to email-verified users and the viewer isn't verified, or when the two users have blocked
    each other (either direction). Always 404 (never 403) so existence isn't revealed. You can
    always see your own profile. Cheap attribute checks run before the block DB query.
    """
    if profile.user_id == viewer.id:
        return
    if (
        profile.is_hidden
        or (profile.show_profile_to_verified_only and not viewer.is_verified)
        or await users_are_blocked(db, viewer.id, profile.user_id)
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Profile not found')
