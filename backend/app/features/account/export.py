"""Build a machine-readable export of the caller's own account data (privacy right of access).

Synchronous JSON for campus-scale volumes. Caps large collections so one request cannot
DoS the DB. Secrets (password hashes, OTPs, raw push tokens) are never included.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import (
    Activity,
    ActivityParticipant,
    Block,
    ConnectionRequest,
    ConversationMember,
    DeviceToken,
    Group,
    Interest,
    LookingForOption,
    Match,
    Message,
    Notification,
    Profile,
    ProgramMembership,
    Report,
    ScholarProfessionalProfile,
    User,
    UserLanguage,
)
from app.shared.audit import record_audit

_MESSAGE_CAP = 2_000
_NOTIFICATION_CAP = 500


def _iso(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.isoformat()


def _id(value: UUID | None) -> str | None:
    return str(value) if value is not None else None


async def build_account_export(db: AsyncSession, user: User) -> dict[str, Any]:
    """Assemble the export payload and record ``account.export`` on the audit trail."""
    user_id = user.id
    profile = (
        await db.execute(
            select(Profile)
            .where(Profile.user_id == user_id)
            .options(
                selectinload(Profile.interests),
                selectinload(Profile.looking_for_options),
                selectinload(Profile.languages).selectinload(UserLanguage.language),
            )
        )
    ).scalar_one_or_none()

    payload: dict[str, Any] = {
        'exported_at': _iso(datetime.now(UTC)),
        'schema_version': 1,
        'account': {
            'id': _id(user.id),
            'email': user.email,
            'role': user.role,
            'status': user.status,
            'is_active': user.is_active,
            'is_verified': user.is_verified,
            'created_at': _iso(user.created_at),
            'updated_at': _iso(user.updated_at),
        },
        'profile': _profile_dict(profile) if profile else None,
        'connection_requests': await _connection_requests(db, user_id),
        'matches': await _matches(db, user_id),
        'blocks': await _blocks(db, user_id),
        'messages_sent': await _messages_sent(db, user_id),
        'conversation_memberships': await _memberships(db, user_id),
        'groups_owned': await _groups_owned(db, user_id),
        'activities_created': await _activities_created(db, user_id),
        'activity_participations': await _activity_participations(db, user_id),
        'reports_filed': await _reports(db, Report.reporter_id == user_id),
        'reports_about_you': await _reports(db, Report.reported_user_id == user_id),
        'notifications': await _notifications(db, user_id),
        'device_tokens': await _device_tokens(db, user_id),
        'program_memberships': await _program_memberships(db, user_id),
        'scholar_profile': await _scholar_profile(db, user_id),
    }

    await record_audit(
        db,
        actor_id=user_id,
        action='account.export',
        target_type='user',
        target_id=user_id,
        after_data={
            'schema_version': 1,
            'messages_sent_count': len(payload['messages_sent']),
            'notifications_count': len(payload['notifications']),
        },
    )
    await db.commit()
    return payload


def _profile_dict(profile: Profile) -> dict[str, Any]:
    interests: list[Interest] = list(profile.interests or [])
    looking: list[LookingForOption] = list(profile.looking_for_options or [])
    langs = list(profile.languages or [])
    return {
        'id': _id(profile.id),
        'display_name': profile.display_name,
        'pronouns': profile.pronouns,
        'major': profile.major,
        'class_year': profile.class_year,
        'country_state': profile.country_state,
        'campus': profile.campus,
        'bio': profile.bio,
        'avatar_url': profile.avatar_url,
        'is_hidden': profile.is_hidden,
        'profile_completed': profile.profile_completed,
        'interests': [i.name for i in interests],
        'looking_for': [o.name for o in looking],
        'languages': [
            {
                'name': ul.language.name if ul.language else None,
                'kind': ul.kind,
            }
            for ul in langs
        ],
        'created_at': _iso(profile.created_at),
        'updated_at': _iso(profile.updated_at),
    }


async def _connection_requests(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(
            select(ConnectionRequest).where(
                or_(ConnectionRequest.sender_id == user_id, ConnectionRequest.receiver_id == user_id)
            )
        )
    ).scalars().all()
    return [
        {
            'id': _id(r.id),
            'sender_id': _id(r.sender_id),
            'receiver_id': _id(r.receiver_id),
            'status': r.status,
            'created_at': _iso(r.created_at),
        }
        for r in rows
    ]


async def _matches(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(
            select(Match).where(or_(Match.user_a_id == user_id, Match.user_b_id == user_id))
        )
    ).scalars().all()
    return [
        {
            'id': _id(m.id),
            'user_a_id': _id(m.user_a_id),
            'user_b_id': _id(m.user_b_id),
            'created_at': _iso(m.created_at),
        }
        for m in rows
    ]


async def _blocks(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(
            select(Block).where(or_(Block.blocker_id == user_id, Block.blocked_id == user_id))
        )
    ).scalars().all()
    return [
        {
            'id': _id(b.id),
            'blocker_id': _id(b.blocker_id),
            'blocked_id': _id(b.blocked_id),
            'created_at': _iso(b.created_at),
        }
        for b in rows
    ]


async def _messages_sent(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(
            select(Message)
            .where(Message.sender_id == user_id)
            .order_by(Message.created_at.desc())
            .limit(_MESSAGE_CAP)
        )
    ).scalars().all()
    return [
        {
            'id': _id(m.id),
            'conversation_id': _id(m.conversation_id),
            'match_id': _id(m.match_id),
            'body': m.body if m.deleted_at is None else None,
            'deleted': m.deleted_at is not None,
            'client_message_id': _id(m.client_message_id),
            'created_at': _iso(m.created_at),
            'deleted_at': _iso(m.deleted_at),
        }
        for m in rows
    ]


async def _memberships(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(select(ConversationMember).where(ConversationMember.user_id == user_id))
    ).scalars().all()
    return [
        {
            'conversation_id': _id(m.conversation_id),
            'role': m.role,
            'status': m.status,
            'muted': m.muted,
            'joined_at': _iso(m.joined_at),
        }
        for m in rows
    ]


async def _groups_owned(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (await db.execute(select(Group).where(Group.owner_id == user_id))).scalars().all()
    return [
        {
            'id': _id(g.id),
            'name': g.name,
            'category': g.category,
            'conversation_id': _id(g.conversation_id),
            'created_at': _iso(g.created_at),
        }
        for g in rows
    ]


async def _activities_created(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (await db.execute(select(Activity).where(Activity.creator_id == user_id))).scalars().all()
    return [
        {
            'id': _id(a.id),
            'title': a.title,
            'description': a.description,
            'category': a.category,
            'location': a.location,
            'start_time': _iso(a.start_time),
            'is_cancelled': a.is_cancelled,
        }
        for a in rows
    ]


async def _activity_participations(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(select(ActivityParticipant).where(ActivityParticipant.user_id == user_id))
    ).scalars().all()
    return [
        {
            'activity_id': _id(p.activity_id),
            'status': p.status,
            'joined_at': _iso(p.created_at),
        }
        for p in rows
    ]


async def _reports(db: AsyncSession, clause: Any) -> list[dict[str, Any]]:
    rows = (await db.execute(select(Report).where(clause))).scalars().all()
    return [
        {
            'id': _id(r.id),
            'reporter_id': _id(r.reporter_id),
            'reported_user_id': _id(r.reported_user_id),
            'activity_id': _id(r.activity_id),
            'group_id': _id(r.group_id),
            'message_id': _id(r.message_id),
            'reason': r.reason,
            'details': r.details,
            'status': r.status,
            'created_at': _iso(r.created_at),
        }
        for r in rows
    ]


async def _notifications(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(
            select(Notification)
            .where(Notification.user_id == user_id)
            .order_by(Notification.created_at.desc())
            .limit(_NOTIFICATION_CAP)
        )
    ).scalars().all()
    return [
        {
            'id': _id(n.id),
            'type': n.type,
            'group_id': _id(n.group_id),
            'actor_id': _id(n.actor_id),
            'read_at': _iso(n.read_at),
            'created_at': _iso(n.created_at),
        }
        for n in rows
    ]


async def _device_tokens(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    """Metadata only — never the raw push token."""
    rows = (await db.execute(select(DeviceToken).where(DeviceToken.user_id == user_id))).scalars().all()
    return [
        {
            'id': _id(t.id),
            'platform': t.platform,
            'created_at': _iso(t.created_at),
        }
        for t in rows
    ]


async def _program_memberships(db: AsyncSession, user_id: UUID) -> list[dict[str, Any]]:
    rows = (
        await db.execute(select(ProgramMembership).where(ProgramMembership.user_id == user_id))
    ).scalars().all()
    return [
        {
            'id': _id(m.id),
            'program_id': _id(m.program_id),
            'status': m.status,
            'verified_at': _iso(m.verified_at),
            'revoked_at': _iso(m.revoked_at),
        }
        for m in rows
    ]


async def _scholar_profile(db: AsyncSession, user_id: UUID) -> dict[str, Any] | None:
    row = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == user_id)
        )
    ).scalar_one_or_none()
    if row is None:
        return None
    return {
        'linkedin_url': row.linkedin_url,
        'handshake_url': row.handshake_url,
        'summary': row.summary,
        'skills': list(row.skills or []),
        'career_interests': list(row.career_interests or []),
        'employer_visibility_consent': row.employer_visibility_consent,
        'consent_given_at': _iso(row.consent_given_at),
        'consent_version': row.consent_version,
        'has_headshot': bool(row.headshot_path),
        'has_resume': bool(row.resume_path),
    }
