"""Self-service account deletion.

We **anonymize in place** rather than hard-delete. Almost every FK to `users.id` is
`ON DELETE CASCADE`, so a hard delete would cascade away *other people's* data: every message the
user sent, any group they own (and its whole chat), and the activities they created. Instead we:

  - transfer ownership of their groups to the next admin/member (delete only if they were alone),
  - cancel their upcoming activities and drop their participations elsewhere,
  - remove them from every group chat (keeping DM history for the other party),
  - clear the social graph (pending requests, blocks, their notifications, push tokens),
  - scrub the profile to a "Deleted user" tombstone and delete the avatar image,
  - anonymize the user row (email/password/auth link) and stamp `deleted_at`,
  - then close their live sockets and delete the Supabase Auth user (best-effort).

Kept intentionally: their **messages** (shown as "Deleted user"), **DM conversations/matches**
(the other party's history), and **reports** filed by or about them (moderation must survive).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import delete, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.realtime.runtime import disconnect_user
from app.models import (
    Activity,
    ActivityParticipant,
    Block,
    ConnectionRequest,
    Conversation,
    ConversationMember,
    DeviceToken,
    Group,
    Notification,
    Profile,
    User,
    UserLanguage,
    profile_interests,
    user_looking_for,
)
from app.shared.storage import storage_service
from app.shared.supabase_admin import delete_auth_user

logger = logging.getLogger(__name__)


async def _reassign_or_delete_owned_groups(db: AsyncSession, user_id: UUID) -> None:
    """Hand each owned group to its next steward (admins first, then earliest joiner). A group
    with no other active member is deleted via its conversation (cascades chat + memberships)."""
    groups = (await db.execute(select(Group).where(Group.owner_id == user_id))).scalars().all()
    for group in groups:
        replacement = (
            await db.execute(
                select(ConversationMember)
                .where(
                    ConversationMember.conversation_id == group.conversation_id,
                    ConversationMember.user_id != user_id,
                    ConversationMember.status == 'active',
                )
                .order_by((ConversationMember.role == 'admin').desc(), ConversationMember.joined_at.asc())
            )
        ).scalars().first()
        if replacement is None:
            # Sole member — deleting the conversation cascades the group, members, and messages.
            await db.execute(delete(Conversation).where(Conversation.id == group.conversation_id))
        else:
            group.owner_id = replacement.user_id
            replacement.role = 'owner'


async def delete_account(db: AsyncSession, user: User) -> None:
    """Anonymize the caller's account in place and revoke their access. Commits once, then does
    the external cleanup (sockets + Supabase Auth) — those never block the deletion."""
    user_id = user.id
    auth_user_id = user.auth_user_id  # capture before we unlink it
    now = datetime.now(UTC)

    # 1. Owned groups → transfer (or delete if they were the only member).
    await _reassign_or_delete_owned_groups(db, user_id)

    # 2. Activities: cancel their upcoming ones (no orphan events), drop their participations.
    await db.execute(
        update(Activity)
        .where(Activity.creator_id == user_id, Activity.is_cancelled.is_(False), Activity.start_time >= now)
        .values(is_cancelled=True)
    )
    await db.execute(delete(ActivityParticipant).where(ActivityParticipant.user_id == user_id))

    # 3. Leave every GROUP chat; keep DM memberships so the other party's thread still resolves.
    group_conversations = select(Conversation.id).where(Conversation.kind == 'group')
    await db.execute(
        delete(ConversationMember).where(
            ConversationMember.user_id == user_id,
            ConversationMember.conversation_id.in_(group_conversations),
        )
    )

    # 4. Social graph: pending requests, blocks, their notification inbox, push tokens.
    await db.execute(
        delete(ConnectionRequest).where(
            or_(ConnectionRequest.sender_id == user_id, ConnectionRequest.receiver_id == user_id)
        )
    )
    await db.execute(delete(Block).where(or_(Block.blocker_id == user_id, Block.blocked_id == user_id)))
    await db.execute(delete(Notification).where(Notification.user_id == user_id))
    await db.execute(delete(DeviceToken).where(DeviceToken.user_id == user_id))

    # 5. Profile → "Deleted user" tombstone; wipe personal data + avatar.
    profile = (await db.execute(select(Profile).where(Profile.user_id == user_id))).scalar_one_or_none()
    if profile is not None:
        await db.execute(delete(UserLanguage).where(UserLanguage.profile_id == profile.id))
        await db.execute(delete(profile_interests).where(profile_interests.c.profile_id == profile.id))
        await db.execute(delete(user_looking_for).where(user_looking_for.c.profile_id == profile.id))
        profile.display_name = 'Deleted user'
        profile.pronouns = None
        profile.major = None
        profile.class_year = None
        profile.country_state = None
        profile.bio = None
        profile.avatar_url = None
        profile.is_hidden = True
        profile.profile_completed = False
        storage_service.delete_profile_image(user_id)

    # 6. Anonymize the user row and revoke access (is_active=False → auth deps reject immediately).
    user.email = f'deleted+{user_id}@deleted.invalid'
    user.password_hash = None
    user.auth_user_id = None
    user.status = 'deleted'
    user.is_active = False
    user.is_verified = False
    user.verify_otp_hash = None
    user.verify_otp_expires_at = None
    user.reset_otp_hash = None
    user.reset_otp_expires_at = None
    user.deleted_at = now

    await db.commit()

    # 7. External cleanup — best-effort, must not fail the deletion.
    await disconnect_user(user_id)
    if auth_user_id is not None and not delete_auth_user(str(auth_user_id)):
        logger.warning('delete_account: Supabase auth user %s not removed; local row anonymized', auth_user_id)
