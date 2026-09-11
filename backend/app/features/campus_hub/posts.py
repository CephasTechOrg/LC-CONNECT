"""Public campus posts — published, audience-scoped content."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_hub.content_visibility import is_post_visible, published_posts_stmt
from app.models import CampusPost, CampusPostRead, User
from app.shared.link_preview import link_preview_dict


def _summary(post: CampusPost, *, read: bool = False) -> dict:
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
        'link_preview': link_preview_dict(post),
        'read': read,
        'source': post.source,
        'is_blueprint_bond': post.eligible_program_slug is not None,
    }


def _read_exists(user: User):
    """Correlated EXISTS: has this user read the current CampusPost row?"""
    return (
        select(CampusPostRead.id)
        .where(CampusPostRead.post_id == CampusPost.id, CampusPostRead.user_id == user.id)
        .exists()
    )


def _seen(user: User):
    """Whether the user should see this post as already-read.

    True when they actually read it, *or* when it was published before their account existed.
    The badge and the per-post dots have to agree: counting only post-signup announcements while
    still dotting the whole back catalogue as unread would show a badge of 0 above a feed of
    unread markers.
    """
    return or_(_read_exists(user), CampusPost.publish_at < user.created_at)


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
    offset: int = 0,
) -> list[dict]:
    stmt = published_posts_stmt(user=user).add_columns(_seen(user).label('read'))
    if kind:
        stmt = stmt.where(CampusPost.kind == kind.strip().lower())
    if priority:
        stmt = stmt.where(CampusPost.priority == priority.strip().lower())
    if category:
        stmt = stmt.where(CampusPost.category == category.strip().lower())
    # Stable order for offset paging: newest first, id as the tiebreaker.
    stmt = stmt.order_by(CampusPost.publish_at.desc(), CampusPost.id.desc()).limit(limit).offset(offset)
    rows = (await db.execute(stmt)).all()
    return [_summary(post, read=bool(read)) for post, read in rows]


async def get_post(db: AsyncSession, *, user: User, post_id: UUID) -> dict:
    post = await db.get(CampusPost, post_id)
    if post is None or not await is_post_visible(db, post, user=user):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Campus post not found')
    return _detail(post)


async def build_overview(db: AsyncSession, *, user: User) -> dict:
    now = datetime.now(UTC)
    base = published_posts_stmt(user=user, now=now).add_columns(_seen(user).label('read'))
    urgent = (
        await db.execute(
            base.where(CampusPost.priority == 'urgent').order_by(CampusPost.publish_at.desc()).limit(3)
        )
    ).all()
    updates = (
        await db.execute(
            base.where(CampusPost.kind == 'announcement').order_by(CampusPost.publish_at.desc()).limit(5)
        )
    ).all()
    return {
        'urgent_posts': [_summary(post, read=bool(read)) for post, read in urgent],
        'latest_updates': [_summary(post, read=bool(read)) for post, read in updates],
    }


# ── announcement read state (per-user, mirrors notification read tracking) ────────


def _visible_announcements_stmt(user: User):
    """Announcements the user can currently see (published, in-window, correct audience)."""
    return published_posts_stmt(user=user).where(CampusPost.kind == 'announcement')


async def announcement_total(db: AsyncSession, user: User, *, category: str | None = None) -> int:
    """Total visible announcements (optionally in one category) — the 'of N' in 'showing X of N'."""
    stmt = _visible_announcements_stmt(user)
    if category:
        stmt = stmt.where(CampusPost.category == category.strip().lower())
    return int((await db.execute(select(func.count()).select_from(stmt.subquery()))).scalar_one())


async def unread_announcement_count(db: AsyncSession, user: User) -> int:
    """How many visible announcements this user has not read yet — the badge number.

    Only counts announcements published *since the account was created*. "Unread" was otherwise
    defined purely as "no read receipt exists", and a brand-new account has none — so every
    announcement ever published counted, and a student's very first sight of the app was a badge
    reading the size of the entire back catalogue. Nothing there was addressed to them; they
    simply had not existed yet.

    The history stays fully readable in the feed. This changes what counts as *new to you*, which
    is the only thing a badge can usefully mean.
    """
    unread = (
        _visible_announcements_stmt(user)
        .where(~_seen(user))
        .subquery()
    )
    return int((await db.execute(select(func.count()).select_from(unread))).scalar_one())


async def mark_announcement_read(db: AsyncSession, user: User, post_id: UUID) -> None:
    """Mark one announcement read (idempotent). 404 unless it's an announcement the user can see."""
    post = await db.get(CampusPost, post_id)
    if post is None or post.kind != 'announcement' or not await is_post_visible(db, post, user=user):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Announcement not found')
    await db.execute(
        pg_insert(CampusPostRead)
        .values(user_id=user.id, post_id=post_id)
        .on_conflict_do_nothing(index_elements=['user_id', 'post_id'])
    )
    await db.commit()


async def mark_all_announcements_read(db: AsyncSession, user: User) -> None:
    """Mark every currently-visible announcement read (bulk API helper — not used on list-open)."""
    visible = _visible_announcements_stmt(user).subquery()
    ids = (await db.execute(select(visible.c.id))).scalars().all()
    if not ids:
        return
    await db.execute(
        pg_insert(CampusPostRead)
        .values([{'user_id': user.id, 'post_id': pid} for pid in ids])
        .on_conflict_do_nothing(index_elements=['user_id', 'post_id'])
    )
    await db.commit()
