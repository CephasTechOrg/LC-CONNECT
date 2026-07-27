"""Public campus posts — published, audience-scoped content."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_hub.content_visibility import is_post_visible, published_posts_stmt
from app.models import CampusPost, User


def _summary(post: CampusPost) -> dict:
    return {
        'id': post.id,
        'kind': post.kind,
        'title': post.title,
        'summary': post.summary,
        'priority': post.priority,
        'category': post.category,
        'publish_at': post.publish_at,
        'expires_at': post.expires_at,
        'external_url': post.external_url,
    }


def _detail(post: CampusPost) -> dict:
    return {
        **_summary(post),
        'body': post.body,
        'audience': post.audience,
    }


async def list_posts(
    db: AsyncSession,
    *,
    user: User,
    kind: str | None = None,
    priority: str | None = None,
    category: str | None = None,
    limit: int = 50,
) -> list[dict]:
    stmt = published_posts_stmt(user=user)
    if kind:
        stmt = stmt.where(CampusPost.kind == kind.strip().lower())
    if priority:
        stmt = stmt.where(CampusPost.priority == priority.strip().lower())
    if category:
        stmt = stmt.where(CampusPost.category == category.strip().lower())
    stmt = stmt.order_by(CampusPost.publish_at.desc()).limit(limit)
    posts = (await db.execute(stmt)).scalars().all()
    return [_summary(post) for post in posts]


async def get_post(db: AsyncSession, *, user: User, post_id: UUID) -> dict:
    post = await db.get(CampusPost, post_id)
    if post is None or not is_post_visible(post, user=user):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Campus post not found')
    return _detail(post)


async def build_overview(db: AsyncSession, *, user: User) -> dict:
    now = datetime.now(UTC)
    base = published_posts_stmt(user=user, now=now)
    urgent = (
        await db.execute(
            base.where(CampusPost.priority == 'urgent').order_by(CampusPost.publish_at.desc()).limit(3)
        )
    ).scalars().all()
    updates = (
        await db.execute(
            base.where(CampusPost.kind == 'update').order_by(CampusPost.publish_at.desc()).limit(5)
        )
    ).scalars().all()
    deadlines = (
        await db.execute(
            base.where(CampusPost.kind == 'deadline')
            .order_by(CampusPost.expires_at.asc().nulls_last(), CampusPost.publish_at.desc())
            .limit(5)
        )
    ).scalars().all()
    return {
        'urgent_posts': [_summary(post) for post in urgent],
        'latest_updates': [_summary(post) for post in updates],
        'upcoming_deadlines': [_summary(post) for post in deadlines],
    }
