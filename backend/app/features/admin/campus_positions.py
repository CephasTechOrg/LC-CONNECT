"""Admin review workflow for campus positions."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_hub import publishing
from app.models import CampusPosition, CampusPost, Profile, User
from app.shared.audit import record_audit


def _position_snapshot(position: CampusPosition) -> dict[str, str | None]:
    return {
        'status': position.status,
        'official_title': position.official_title,
        'department': position.department,
        'category': position.category,
        'review_note': position.review_note,
    }


async def get_position_or_404(db: AsyncSession, position_id: UUID) -> CampusPosition:
    position = await db.get(CampusPosition, position_id)
    if position is None or not position.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Campus position not found')
    return position


async def list_positions(
    db: AsyncSession, *, status: str = 'pending', limit: int = 100
) -> list[tuple[CampusPosition, User, Profile]]:
    rows = (
        await db.execute(
            select(CampusPosition, User, Profile)
            .join(User, User.id == CampusPosition.user_id)
            .join(Profile, Profile.user_id == User.id)
            .where(CampusPosition.status == status, CampusPosition.is_active.is_(True))
            .order_by(CampusPosition.created_at.asc())
            .limit(limit)
        )
    ).all()
    return list(rows)


async def list_pending_positions(db: AsyncSession, *, limit: int = 100) -> list[tuple[CampusPosition, User, Profile]]:
    return await list_positions(db, status='pending', limit=limit)


async def get_position_detail(
    db: AsyncSession,
    position_id: UUID,
) -> tuple[CampusPosition, User, Profile]:
    row = (
        await db.execute(
            select(CampusPosition, User, Profile)
            .join(User, User.id == CampusPosition.user_id)
            .join(Profile, Profile.user_id == User.id)
            .where(CampusPosition.id == position_id, CampusPosition.is_active.is_(True))
        )
    ).one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Campus position not found')
    return row


async def approve_position(db: AsyncSession, *, actor: User, position_id: UUID) -> CampusPosition:
    position = await get_position_or_404(db, position_id)
    if position.status != 'pending':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only pending positions can be approved')

    before = _position_snapshot(position)
    now = datetime.now(UTC)
    position.status = 'verified'
    position.verified_by_id = actor.id
    position.verified_at = now
    position.review_note = None

    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_position.approve',
        target_type='campus_position',
        target_id=position.id,
        before_data=before,
        after_data=_position_snapshot(position),
    )
    await db.commit()
    await db.refresh(position)
    return position


async def reject_position(
    db: AsyncSession,
    *,
    actor: User,
    position_id: UUID,
    review_note: str | None,
) -> CampusPosition:
    position = await get_position_or_404(db, position_id)
    if position.status != 'pending':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only pending positions can be rejected')

    before = _position_snapshot(position)
    position.status = 'rejected'
    position.verified_by_id = None
    position.verified_at = None
    position.review_note = review_note.strip() if review_note else None

    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_position.reject',
        target_type='campus_position',
        target_id=position.id,
        before_data=before,
        after_data=_position_snapshot(position),
    )
    await db.commit()
    await db.refresh(position)
    return position


async def archive_authored_posts(db: AsyncSession, *, actor: User, author_id: UUID) -> int:
    """Pull an author's live posts from the public feed. Returns how many were archived.

    Drafts are left alone — they are already invisible, and republishing them requires a
    verified position the author no longer has.
    """
    published = (
        await db.execute(
            select(CampusPost).where(CampusPost.author_id == author_id, CampusPost.status == 'published')
        )
    ).scalars().all()
    for post in published:
        await publishing.archive_post(db, actor=actor, post_id=post.id)
    return len(published)


async def revoke_position(
    db: AsyncSession,
    *,
    actor: User,
    position_id: UUID,
    review_note: str | None,
    archive_posts: bool = False,
) -> CampusPosition:
    position = await get_position_or_404(db, position_id)
    if position.status != 'verified':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only verified positions can be revoked')

    before = _position_snapshot(position)
    position.status = 'revoked'
    position.review_note = review_note.strip() if review_note else None

    await record_audit(
        db,
        actor_id=actor.id,
        action='campus_position.revoke',
        target_type='campus_position',
        target_id=position.id,
        before_data=before,
        after_data=_position_snapshot(position),
    )
    await db.commit()
    await db.refresh(position)

    # The position was this user's licence to message anyone — drop their live staff threads.
    # Lazy import avoids a module-load cycle with the realtime package.
    from app.features.realtime.runtime import revoke_staff_conversations

    await revoke_staff_conversations(position.user_id)

    if archive_posts:
        await archive_authored_posts(db, actor=actor, author_id=position.user_id)
    return position
