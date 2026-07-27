"""Shared helpers for published campus content visibility."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import or_, select
from sqlalchemy.sql import Select

from app.models import CampusPost, User


def audiences_for_role(role: str) -> list[str]:
    if role == 'admin':
        return ['all', 'students', 'staff']
    if role == 'staff':
        return ['all', 'staff']
    return ['all', 'students']


def published_posts_stmt(*, user: User, now: datetime | None = None) -> Select:
    now = now or datetime.now(UTC)
    return select(CampusPost).where(
        CampusPost.status == 'published',
        CampusPost.publish_at.is_not(None),
        CampusPost.publish_at <= now,
        or_(CampusPost.expires_at.is_(None), CampusPost.expires_at > now),
        CampusPost.audience.in_(audiences_for_role(user.role)),
    )


def is_post_visible(post: CampusPost, *, user: User, now: datetime | None = None) -> bool:
    now = now or datetime.now(UTC)
    if post.status != 'published' or post.publish_at is None or post.publish_at > now:
        return False
    if post.expires_at is not None and post.expires_at <= now:
        return False
    return post.audience in audiences_for_role(user.role)
