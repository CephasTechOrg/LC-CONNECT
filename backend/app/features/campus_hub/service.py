"""Public campus directory — verified positions only."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CampusPosition, Profile, User


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
    limit: int = 100,
) -> list[dict]:
    stmt = _directory_base()
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


async def get_directory_entry(db: AsyncSession, position_id: UUID) -> dict:
    row = (
        await db.execute(_directory_base().where(CampusPosition.id == position_id))
    ).one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Directory entry not found')
    position, profile, user = row
    return _entry(position, profile, user)
