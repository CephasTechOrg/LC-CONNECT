"""Cross-feature authorization policies.

`users_are_blocked` is a relationship policy used by the connections, messages, and
safety features. Future policies (can_view_profile, can_connect, can_message) belong
here too — see architecture_review/00_current_state_review.md.
"""

from __future__ import annotations

from collections.abc import Sequence
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.features.campus_positions.service import get_primary_position
from app.models import Block, CampusPosition, ConversationMember, Match, Profile, User


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


async def can_message_as_staff(db: AsyncSession, user: User) -> bool:
    """True if `user` may message any active user directly (no connection required).

    Requires `STAFF_MESSAGING_ENABLED`, a `staff` role, and a verified primary campus
    position — the same "official identity" bar as staff publishing
    (`campus_hub.publishing.staff_can_publish`), so a bare `@livingstone.edu` signup
    can't message students until an admin has verified who they actually are.
    """
    if not settings.staff_messaging_enabled:
        return False
    if user.role != 'staff':
        return False
    position = await get_primary_position(db, user.id)
    return position is not None and position.status == 'verified'


async def open_staff_thread_ids(db: AsyncSession, conversation_ids: Sequence[UUID]) -> set[UUID]:
    """Of `conversation_ids`, the `staff_dm`s that still have an official party in them.

    A staff conversation exists only because one side was a verified staff messenger, so it
    stays usable only while that remains true. Revoking the position (or flipping
    `STAFF_MESSAGING_ENABLED` off) therefore closes the thread for *both* sides rather than
    leaving an ex-official channel open.

    This is the set-based form of `can_message_as_staff` — one query for a whole inbox
    instead of a per-user check. Keep the two predicates in sync.
    """
    if not settings.staff_messaging_enabled or not conversation_ids:
        return set()
    rows = await db.execute(
        select(ConversationMember.conversation_id)
        .join(CampusPosition, CampusPosition.user_id == ConversationMember.user_id)
        .join(User, User.id == ConversationMember.user_id)
        .where(
            ConversationMember.conversation_id.in_(conversation_ids),
            ConversationMember.status == 'active',
            User.role == 'staff',
            CampusPosition.is_primary.is_(True),
            CampusPosition.is_active.is_(True),
            CampusPosition.status == 'verified',
        )
    )
    return set(rows.scalars().all())


async def staff_thread_is_open(db: AsyncSession, conversation_id: UUID) -> bool:
    return conversation_id in await open_staff_thread_ids(db, [conversation_id])


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
