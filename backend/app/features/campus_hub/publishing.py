"""Campus post authoring — shared by admin and verified-staff publishers.

Rules:
- Admins (aal2 routes) may manage any post.
- Staff may author only when STAFF_PUBLISHING_ENABLED and they hold a
  verified primary campus position (official identity, not just a staff email).
- Staff may only mutate their own posts.
- Staff may not set priority=urgent (campus-wide alert blast stays admin-only).
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.features.campus_hub.schema import CampusPostCreate, CampusPostUpdate
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
    # (future publish_at) posts wait — nothing to announce yet.
    if post.kind == 'announcement' and post.publish_at is not None and post.publish_at <= now:
        from app.features.realtime import runtime

        await runtime.broadcast_announcement(post.audience)
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
