"""Public campus directory — verified positions only."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Block, CampusPosition, Profile, User


def _directory_base():
    return (
        select(CampusPosition, Profile, User)
        .join(User, User.id == CampusPosition.user_id)
        .join(Profile, Profile.user_id == User.id)
        .where(
            CampusPosition.status == 'verified',
            CampusPosition.is_active.is_(True),
            CampusPosition.is_primary.is_(True),
            User.is_active.is_(True),
            User.status == 'active',
            User.deleted_at.is_(None),
        )
    )


def _entry(position: CampusPosition, profile: Profile, user: User) -> dict:
    return {
        'position_id': position.id,
        'user_id': user.id,
        'display_name': profile.display_name,
        'avatar_url': profile.avatar_url,
        'category': position.category,
        'official_title': position.official_title,
        'department': position.department,
        'office_location': position.office_location,
        'phone': position.phone,
        'contact_email': position.contact_email,
        'availability': position.availability,
        'bio': position.bio or profile.bio,
        'verified_at': position.verified_at,
    }


async def list_directory(
    db: AsyncSession,
    *,
    category: str | None = None,
    department: str | None = None,
    query: str | None = None,
    exclude_user_id: UUID | None = None,
    limit: int = 100,
) -> list[dict]:
    stmt = _directory_base()
    if exclude_user_id is not None:
        stmt = stmt.where(CampusPosition.user_id != exclude_user_id)
    if category:
        stmt = stmt.where(CampusPosition.category == category.strip().lower())
    if department:
        pattern = f'%{department.strip().lower()}%'
        stmt = stmt.where(func.lower(CampusPosition.department).like(pattern))
    if query:
        q = f'%{query.strip().lower()}%'
        stmt = stmt.where(
            or_(
                func.lower(CampusPosition.official_title).like(q),
                func.lower(CampusPosition.department).like(q),
                func.lower(Profile.display_name).like(q),
            )
        )
    stmt = stmt.order_by(CampusPosition.department.asc(), CampusPosition.official_title.asc()).limit(limit)
    rows = (await db.execute(stmt)).all()
    return [_entry(position, profile, user) for position, profile, user in rows]


async def list_students(
    db: AsyncSession,
    *,
    query: str | None = None,
    exclude_user_id: UUID,
    limit: int = 50,
) -> list[dict]:
    """Active, verified students for the staff-facing student directory. Excludes hidden and
    incomplete profiles, the caller, and anyone in a block relationship with them."""
    blocks = (
        await db.execute(
            select(Block).where(or_(Block.blocker_id == exclude_user_id, Block.blocked_id == exclude_user_id))
        )
    ).scalars().all()
    blocked_ids = {b.blocked_id if b.blocker_id == exclude_user_id else b.blocker_id for b in blocks}
    excluded = {exclude_user_id} | blocked_ids

    stmt = (
        select(Profile, User)
        .join(User, User.id == Profile.user_id)
        .where(
            User.role == 'student',
            User.is_active.is_(True),
            User.status == 'active',
            User.is_verified.is_(True),
            User.deleted_at.is_(None),
            Profile.is_hidden.is_(False),
            Profile.profile_completed.is_(True),
            Profile.user_id.not_in(excluded),
        )
    )
    if query:
        q = f'%{query.strip().lower()}%'
        stmt = stmt.where(
            or_(func.lower(Profile.display_name).like(q), func.lower(Profile.major).like(q))
        )
    stmt = stmt.order_by(Profile.display_name.asc()).limit(limit)
    rows = (await db.execute(stmt)).all()
    return [
        {
            'profile_id': profile.id,
            'user_id': user.id,
            'display_name': profile.display_name,
            'avatar_url': profile.avatar_url,
            'major': profile.major,
            'class_year': profile.class_year,
        }
        for profile, user in rows
    ]


async def get_directory_entry(db: AsyncSession, position_id: UUID) -> dict:
    row = (
        await db.execute(_directory_base().where(CampusPosition.id == position_id))
    ).one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Directory entry not found')
    position, profile, user = row
    return _entry(position, profile, user)
