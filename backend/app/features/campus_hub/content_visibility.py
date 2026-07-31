"""Shared helpers for published campus content visibility."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import Select

from app.models import CampusPost, Program, ProgramMembership, User
from app.shared.programs import is_active_program_member


def audiences_for_role(role: str) -> list[str]:
    if role == 'admin':
        return ['all', 'students', 'staff']
    if role == 'staff':
        return ['all', 'staff']
    return ['all', 'students']


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
        CampusPost.audience.in_(audiences_for_role(user.role)),
        or_(CampusPost.eligible_program_slug.is_(None), _eligible_for_program(user.id)),
    )


async def is_post_visible(db: AsyncSession, post: CampusPost, *, user: User, now: datetime | None = None) -> bool:
    now = now or datetime.now(UTC)
    if post.status != 'published' or post.publish_at is None or post.publish_at > now:
        return False
    if post.expires_at is not None and post.expires_at <= now:
        return False
    if post.audience not in audiences_for_role(user.role):
        return False
    if post.eligible_program_slug is not None:
        return await is_active_program_member(db, user.id, post.eligible_program_slug)
    return True
