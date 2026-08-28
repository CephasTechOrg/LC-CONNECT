"""Self-service account deletion.

We **anonymize in place** rather than hard-delete. Almost every FK to `users.id` is
`ON DELETE CASCADE`, so a hard delete would cascade away *other people's* data: every message the
user sent, any group they own (and its whole chat), and the activities they created. Instead we:

  - transfer ownership of their groups to the next admin/member (delete only if they were alone),
  - cancel their upcoming activities and drop their participations elsewhere,
  - remove them from every group chat (keeping DM history for the other party),
  - clear the social graph (pending requests, blocks, their notifications, push tokens),
  - scrub the profile to a "Deleted user" tombstone and delete the avatar image,
  - drop their Blueprint Bond professional profile row + private headshot/résumé files,
  - anonymize the user row (email/password/auth link) and stamp `deleted_at`,
  - then close their live sockets and delete the Supabase Auth user (best-effort).

Kept intentionally: their **messages** (shown as "Deleted user"), **DM conversations/matches**
(the other party's history), and **reports** filed by or about them (moderation must survive).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.realtime.runtime import disconnect_user
from app.models import (
    Activity,
    ActivityParticipant,
    AdminMembership,
    Block,
    ConnectionRequest,
    Conversation,
    ConversationMember,
    DeviceToken,
    Group,
    Notification,
    Profile,
    ScholarProfessionalProfile,
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


async def _assert_not_last_super_admin(db: AsyncSession, user_id: UUID) -> None:
    """Refuse to delete the platform's only Super Admin.

    Only a Super Admin can create a Super Admin, so this deletion would leave nobody able to
    grant the role again — the admin system would be permanently unrecoverable without direct
    database access. The remedy is entirely in the caller's hands (appoint a second Super Admin,
    or have this one's membership revoked first), so this blocks a footgun rather than trapping
    anyone in an account they cannot leave.
    """
    holds_it = (
        await db.execute(
            select(AdminMembership.id).where(
                AdminMembership.user_id == user_id,
                AdminMembership.role == 'super_admin',
                AdminMembership.status == 'active',
            )
        )
    ).scalar_one_or_none()
    if holds_it is None:
        return
    total = int(
        (
            await db.execute(
                select(func.count(AdminMembership.id)).where(
                    AdminMembership.role == 'super_admin', AdminMembership.status == 'active'
                )
            )
        ).scalar_one()
    )
    if total <= 1:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='You are the only Super Admin. Appoint another Super Admin, or have your admin '
            'access revoked, before deleting this account.',
        )


async def delete_account(db: AsyncSession, user: User) -> None:
    """Anonymize the caller's account in place and revoke their access. Commits once, then does
    the external cleanup (sockets + Supabase Auth) — those never block the deletion."""
    await _assert_not_last_super_admin(db, user.id)
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
    await db.execute(delete(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == user_id))

    # Retire any admin roles. Left active these would keep a deleted person on the admin roster
    # (joined to a "Deleted user" profile) and — worse — keep counting toward the
    # last-Super-Admin guard, so the true last Super Admin could revoke themselves believing a
    # second one still existed. Revoked rather than deleted, so the audit trail survives.
    await db.execute(
        update(AdminMembership)
        .where(AdminMembership.user_id == user_id, AdminMembership.status == 'active')
        .values(status='revoked', revoked_at=now)
    )

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
    user.auth_user_id = None
    user.status = 'deleted'
    user.is_active = False
    user.is_verified = False
    user.deleted_at = now

    await db.commit()

    # 7. External cleanup — best-effort, must not fail the deletion.
    await disconnect_user(user_id)
    storage_service.delete_scholar_file(user_id, 'headshot')
    storage_service.delete_scholar_file(user_id, 'resume')
    if auth_user_id is not None and not delete_auth_user(str(auth_user_id)):
        logger.warning('delete_account: Supabase auth user %s not removed; local row anonymized', auth_user_id)
