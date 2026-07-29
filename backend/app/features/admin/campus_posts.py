"""Admin wrappers around shared campus post publishing."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_hub import publishing
from app.features.campus_hub.schema import CampusPostCreate, CampusPostUpdate
from app.models import CampusPost, User
from app.shared.audit import record_audit

get_post_or_404 = publishing.get_post_or_404
recipient_tokens_for_post = publishing.recipient_tokens_for_post


async def list_posts(db: AsyncSession, *, limit: int = 100) -> list[CampusPost]:
    return await publishing.list_all_posts(db, limit=limit)


async def create_post(db: AsyncSession, *, actor: User, payload: CampusPostCreate) -> CampusPost:
    return await publishing.create_post(db, actor=actor, payload=payload, as_staff=False)


async def update_post(
    db: AsyncSession,
    *,
    actor: User,
    post_id: UUID,
    payload: CampusPostUpdate,
) -> CampusPost:
    return await publishing.update_post(db, actor=actor, post_id=post_id, payload=payload, as_staff=False)


async def publish_post(db: AsyncSession, *, actor: User, post_id: UUID) -> CampusPost:
    return await publishing.publish_post(db, actor=actor, post_id=post_id, as_staff=False)


async def archive_post(db: AsyncSession, *, actor: User, post_id: UUID) -> CampusPost:
    return await publishing.archive_post(db, actor=actor, post_id=post_id, as_staff=False)


async def delete_post(db: AsyncSession, *, actor: User, post_id: UUID) -> None:
    """Permanently remove a post (admin only). Archive is the reversible option; this is the
    hard delete for content that should not exist at all. Audited before removal."""
    post = await get_post_or_404(db, post_id)
    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_post.delete',
        target_type='campus_post',
        target_id=post.id,
        before_data={'title': post.title, 'kind': post.kind, 'status': post.status},
        after_data=None,
    )
    await db.delete(post)
    await db.commit()
