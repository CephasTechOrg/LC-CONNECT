"""Shared helpers for published campus content visibility."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import ColumnElement, Select

from app.models import CampusPosition, CampusPost, Program, ProgramMembership, User
from app.shared.programs import is_active_program_member

# Audiences every account may read, whatever their role — the public campus feed.
_PUBLIC_AUDIENCES = ('all',)


def _has_verified_position(user_id) -> Select:
    """Correlated EXISTS for an admin-verified primary campus position.

    `User.role == 'staff'` is inferred from the email domain alone
    (`shared/email_roles.infer_role_from_email`), so it only means "holds a @livingstone.edu
    mailbox" — nobody has checked they actually work here. The verified position is the human
    check, and it's already the bar for staff *publishing* (`publishing.staff_can_publish`) and
    staff *messaging* (`shared/policies.can_message_as_staff`). Reading staff-audience posts is
    held to the same bar so all three agree.
    """
    return (
        select(CampusPosition.id)
        .where(
            CampusPosition.user_id == user_id,
            CampusPosition.is_primary.is_(True),
            CampusPosition.is_active.is_(True),
            CampusPosition.status == 'verified',
        )
        .exists()
    )


def _audience_filter(user: User) -> ColumnElement[bool]:
    """Which post audiences `user` may read.

    Admins are granted explicitly (an `AdminMembership` an existing admin issued), so they read
    everything. A staff account reads staff-audience posts only while its position is verified —
    which also means revoking that position removes the visibility again, rather than leaving an
    ex-staff account reading staff announcements forever.
    """
    if user.role == 'admin':
        return CampusPost.audience.in_(('all', 'students', 'staff'))
    if user.role == 'staff':
        return or_(
            CampusPost.audience.in_(_PUBLIC_AUDIENCES),
            and_(CampusPost.audience == 'staff', _has_verified_position(user.id)),
        )
    return CampusPost.audience.in_(('all', 'students'))


def _eligible_for_program(user_id) -> Select:
    """Correlated EXISTS against the post's `eligible_program_slug` — only ever evaluated for
    the rare post that sets it; every ordinary post (NULL) skips this via the `or_` below."""
    return (
        select(ProgramMembership.id)
        .join(Program, Program.id == ProgramMembership.program_id)
        .where(
            ProgramMembership.user_id == user_id,
            ProgramMembership.status == 'active',
            Program.slug == CampusPost.eligible_program_slug,
        )
        .exists()
    )


def published_posts_stmt(*, user: User, now: datetime | None = None) -> Select:
    now = now or datetime.now(UTC)
    return select(CampusPost).where(
        CampusPost.status == 'published',
        CampusPost.publish_at.is_not(None),
        CampusPost.publish_at <= now,
        or_(CampusPost.expires_at.is_(None), CampusPost.expires_at > now),
        _audience_filter(user),
        or_(CampusPost.eligible_program_slug.is_(None), _eligible_for_program(user.id)),
    )


async def _can_read_audience(db: AsyncSession, audience: str, *, user: User) -> bool:
    """The row-at-a-time twin of `_audience_filter`. Keep the two in sync — a post opened by id
    must never be readable when the same post would be filtered out of the feed."""
    if user.role == 'admin':
        return audience in ('all', 'students', 'staff')
    if user.role == 'staff':
        if audience in _PUBLIC_AUDIENCES:
            return True
        if audience != 'staff':
            return False
        return bool((await db.execute(select(_has_verified_position(user.id)))).scalar())
    return audience in ('all', 'students')


async def is_post_visible(db: AsyncSession, post: CampusPost, *, user: User, now: datetime | None = None) -> bool:
    now = now or datetime.now(UTC)
    if post.status != 'published' or post.publish_at is None or post.publish_at > now:
        return False
    if post.expires_at is not None and post.expires_at <= now:
        return False
    if not await _can_read_audience(db, post.audience, user=user):
        return False
    if post.eligible_program_slug is not None:
        return await is_active_program_member(db, user.id, post.eligible_program_slug)
    return True
