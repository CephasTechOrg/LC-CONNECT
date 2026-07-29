"""Campus post authoring — shared by admin and verified-staff publishers.

Rules:
- Admins (aal2 routes) may manage any post.
- Staff may author only when STAFF_PUBLISHING_ENABLED and they hold a
  verified primary campus position (official identity, not just a staff email).
- Staff may only mutate their own posts.
- Staff may not set priority=urgent (campus-wide alert blast stays admin-only).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.features.campus_hub.schema import CampusPostCreate, CampusPostUpdate, categories_for_kind
from app.features.campus_positions.service import get_primary_position
from app.models import CampusPost, DeviceToken, User
from app.shared.audit import record_audit


def _post_snapshot(post: CampusPost) -> dict[str, str | None]:
    return {
        'status': post.status,
        'kind': post.kind,
        'title': post.title,
        'priority': post.priority,
        'audience': post.audience,
    }


async def get_post_or_404(db: AsyncSession, post_id: UUID) -> CampusPost:
    post = await db.get(CampusPost, post_id)
    if post is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Campus post not found')
    return post


async def staff_can_publish(db: AsyncSession, user: User) -> bool:
    if not settings.staff_publishing_enabled:
        return False
    if user.role == 'admin':
        return True
    if user.role != 'staff':
        return False
    position = await get_primary_position(db, user.id)
    return position is not None and position.status == 'verified'


async def require_staff_publisher(db: AsyncSession, user: User) -> None:
    if user.role == 'admin':
        return
    if not settings.staff_publishing_enabled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Staff publishing is disabled',
        )
    if user.role != 'staff':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Staff publishing requires a staff account')
    if not await staff_can_publish(db, user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='A verified campus position is required before publishing',
        )


def _assert_staff_priority(payload_priority: str | None) -> None:
    if payload_priority == 'urgent':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Only admins can publish urgent campus alerts',
        )


def _assert_owner_or_admin(*, actor: User, post: CampusPost) -> None:
    if actor.role == 'admin':
        return
    if post.author_id != actor.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='You can only manage your own posts')


async def list_all_posts(db: AsyncSession, *, limit: int = 100) -> list[CampusPost]:
    return list(
        (await db.execute(select(CampusPost).order_by(CampusPost.updated_at.desc()).limit(limit))).scalars().all()
    )


async def list_author_posts(db: AsyncSession, *, author_id: UUID, limit: int = 100) -> list[CampusPost]:
    return list(
        (
            await db.execute(
                select(CampusPost)
                .where(CampusPost.author_id == author_id)
                .order_by(CampusPost.updated_at.desc())
                .limit(limit)
            )
        ).scalars().all()
    )


async def create_post(
    db: AsyncSession,
    *,
    actor: User,
    payload: CampusPostCreate,
    as_staff: bool = False,
) -> CampusPost:
    if as_staff:
        await require_staff_publisher(db, actor)
        _assert_staff_priority(payload.priority)

    data = payload.model_dump()
    if data.get('external_url') is not None:
        data['external_url'] = str(data['external_url'])
    post = CampusPost(author_id=actor.id, status='draft', **data)
    db.add(post)
    await db.flush()
    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_post.create',
        target_type='campus_post',
        target_id=post.id,
        before_data=None,
        after_data=_post_snapshot(post),
    )
    await db.commit()
    await db.refresh(post)
    return post


async def update_post(
    db: AsyncSession,
    *,
    actor: User,
    post_id: UUID,
    payload: CampusPostUpdate,
    as_staff: bool = False,
) -> CampusPost:
    post = await get_post_or_404(db, post_id)
    if as_staff:
        await require_staff_publisher(db, actor)
        _assert_owner_or_admin(actor=actor, post=post)
        if payload.priority is not None:
            _assert_staff_priority(payload.priority)

    if post.status == 'archived':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Archived posts cannot be edited')

    before = _post_snapshot(post)
    updates = payload.model_dump(exclude_unset=True)
    if 'external_url' in updates and updates['external_url'] is not None:
        updates['external_url'] = str(updates['external_url'])
    if 'category' in updates and updates['category'] is not None:
        # `kind` may not be part of this partial update — validate against the post's kind as it
        # will be *after* this update (a kind change and a category change can arrive together).
        resolved_kind = updates.get('kind', post.kind)
        if updates['category'] not in categories_for_kind(resolved_kind):
            allowed = ', '.join(sorted(categories_for_kind(resolved_kind)))
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"category for kind={resolved_kind} must be one of: {allowed}",
            )
    for key, value in updates.items():
        setattr(post, key, value)

    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_post.update',
        target_type='campus_post',
        target_id=post.id,
        before_data=before,
        after_data=_post_snapshot(post),
    )
    await db.commit()
    await db.refresh(post)
    return post


async def publish_post(
    db: AsyncSession,
    *,
    actor: User,
    post_id: UUID,
    as_staff: bool = False,
) -> CampusPost:
    post = await get_post_or_404(db, post_id)
    if as_staff:
        await require_staff_publisher(db, actor)
        _assert_owner_or_admin(actor=actor, post=post)
        _assert_staff_priority(post.priority)

    if post.status != 'draft':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only draft posts can be published')

    before = _post_snapshot(post)
    now = datetime.now(UTC)
    post.status = 'published'
    if post.publish_at is None:
        post.publish_at = now

    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_post.publish',
        target_type='campus_post',
        target_id=post.id,
        before_data=before,
        after_data=_post_snapshot(post),
    )
    await db.commit()
    await db.refresh(post)
    # Live ping so students' announcement counter ticks up the moment it goes live. Scheduled
    # (future publish_at) posts wait — nothing to announce yet. Fully isolated: the post is already
    # committed, so a realtime hiccup (or import error) must never fail the publish.
    if post.kind == 'announcement' and post.publish_at is not None and post.publish_at <= now:
        try:
            from app.features.realtime import runtime

            await runtime.broadcast_announcement(post.audience)
        except Exception:  # noqa: BLE001 — the live ping is a side effect, never a blocker
            logging.getLogger(__name__).warning('announcement ping failed for post %s', post.id)
    return post


async def archive_post(
    db: AsyncSession,
    *,
    actor: User,
    post_id: UUID,
    as_staff: bool = False,
) -> CampusPost:
    post = await get_post_or_404(db, post_id)
    if as_staff:
        await require_staff_publisher(db, actor)
        _assert_owner_or_admin(actor=actor, post=post)

    if post.status == 'archived':
        return post

    before = _post_snapshot(post)
    post.status = 'archived'
    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_post.archive',
        target_type='campus_post',
        target_id=post.id,
        before_data=before,
        after_data=_post_snapshot(post),
    )
    await db.commit()
    await db.refresh(post)
    return post


def should_push_on_publish(post: CampusPost, *, now: datetime | None = None) -> bool:
    """Whether a just-published post is worth an FCM push — important/urgent priority and
    actually live now (a future `publish_at` means nothing to announce yet; a scheduling job,
    not this path, would handle that later)."""
    if post.priority not in {'important', 'urgent'}:
        return False
    now = now or datetime.now(UTC)
    return post.publish_at is not None and post.publish_at <= now


async def push_published_post(post_id: UUID) -> None:
    """Send the FCM push for a just-published important/urgent post. Runs as a background task
    (after the response), so it re-reads the post fresh rather than trusting the caller's
    in-memory copy. Shared by both the staff and admin publish routes — this is the one place
    that decides "should this publish page someone."
    """
    from app.database import AsyncSessionLocal
    from app.features.notifications.push import push_sender

    async with AsyncSessionLocal() as db:
        post = await db.get(CampusPost, post_id)
        if post is None or post.status != 'published' or not should_push_on_publish(post):
            return
        tokens = await recipient_tokens_for_post(db, post)
        if tokens:
            await push_sender.notify_campus_post(
                db, tokens=tokens, title=post.title, post_id=post.id, priority=post.priority,
            )


async def recipient_tokens_for_post(db: AsyncSession, post: CampusPost) -> list[str]:
    role_filter = ['student', 'staff', 'admin']
    if post.audience == 'students':
        role_filter = ['student', 'admin']
    elif post.audience == 'staff':
        role_filter = ['staff', 'admin']

    rows = (
        await db.execute(
            select(DeviceToken.token)
            .join(User, User.id == DeviceToken.user_id)
            .where(
                User.is_active.is_(True),
                User.status == 'active',
                User.is_verified.is_(True),
                User.deleted_at.is_(None),
                User.role.in_(role_filter),
            )
        )
    ).all()
    return [row[0] for row in rows]
