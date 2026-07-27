"""Admin CRUD and publishing for official campus posts."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_hub.schema import CampusPostCreate, CampusPostUpdate
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


async def list_posts(db: AsyncSession, *, limit: int = 100) -> list[CampusPost]:
    return list(
        (
            await db.execute(select(CampusPost).order_by(CampusPost.updated_at.desc()).limit(limit))
        ).scalars().all()
    )


async def create_post(db: AsyncSession, *, actor: User, payload: CampusPostCreate) -> CampusPost:
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
) -> CampusPost:
    post = await get_post_or_404(db, post_id)
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


async def publish_post(db: AsyncSession, *, actor: User, post_id: UUID) -> CampusPost:
    post = await get_post_or_404(db, post_id)
    if post.status != 'draft':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only draft posts can be published')

    before = _post_snapshot(post)
    now = datetime.now(UTC)
    post.status = 'published'
    # Explicit publish: if no schedule was set, go live now. Future publish_at is kept
    # so overview/feeds remain gated until that time (scheduled publish).
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
    return post


async def archive_post(db: AsyncSession, *, actor: User, post_id: UUID) -> CampusPost:
    post = await get_post_or_404(db, post_id)
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
    """Device tokens for active verified users in the post audience."""
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
