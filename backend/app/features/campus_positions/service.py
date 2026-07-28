"""Campus position CRUD for the authenticated user's primary position."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.campus_positions.schema import CampusPositionCreate, CampusPositionUpdate
from app.models import CampusPosition, Profile, User
from app.shared.email_roles import normalize_campus_contact_email
from app.shared.onboarding import CAMPUS_CATEGORIES, compute_onboarding_completed


async def get_primary_position(db: AsyncSession, user_id: UUID) -> CampusPosition | None:
    return (
        await db.execute(
            select(CampusPosition).where(
                CampusPosition.user_id == user_id,
                CampusPosition.is_primary.is_(True),
                CampusPosition.is_active.is_(True),
            )
        )
    ).scalar_one_or_none()


def _assert_editable(position: CampusPosition) -> None:
    if position.status == 'verified':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Verified campus positions cannot be edited. Contact an administrator.',
        )


def _account_contact_email(email: str) -> str:
    """A staff member's public contact email is always their account email — never a separate,
    fill-in field. Normalized once here so it can't drift from the login identity."""
    try:
        return normalize_campus_contact_email(email)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


def _mark_resubmitted(position: CampusPosition) -> None:
    """Rejected/revoked edits re-enter the admin review queue as pending."""
    if position.status in {'rejected', 'revoked'}:
        position.status = 'pending'
        position.review_note = None
        position.verified_by_id = None
        position.verified_at = None


async def refresh_profile_completed(db: AsyncSession, user: User, profile: Profile) -> None:
    position = await get_primary_position(db, user.id)
    profile.profile_completed = compute_onboarding_completed(user, profile, position)


async def upsert_primary_position(
    db: AsyncSession,
    user: User,
    profile: Profile,
    payload: CampusPositionCreate,
) -> CampusPosition:
    if payload.category not in CAMPUS_CATEGORIES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid campus category')

    existing = await get_primary_position(db, user.id)
    contact_email = _account_contact_email(user.email)

    if existing is None:
        position = CampusPosition(
            user_id=user.id,
            category=payload.category,
            official_title=payload.official_title.strip(),
            department=payload.department.strip(),
            office_location=payload.office_location.strip() if payload.office_location else None,
            phone=payload.phone.strip() if payload.phone else None,
            contact_email=contact_email,
            availability=payload.availability,
            bio=payload.bio,
            status='pending',
            is_primary=True,
            is_active=True,
        )
        db.add(position)
    else:
        _assert_editable(existing)
        existing.category = payload.category
        existing.official_title = payload.official_title.strip()
        existing.department = payload.department.strip()
        existing.office_location = payload.office_location.strip() if payload.office_location else None
        existing.phone = payload.phone.strip() if payload.phone else None
        existing.contact_email = contact_email
        existing.availability = payload.availability
        existing.bio = payload.bio
        _mark_resubmitted(existing)
        position = existing

    await db.flush()
    await refresh_profile_completed(db, user, profile)
    await db.commit()
    await db.refresh(position)
    return position


async def update_primary_position(
    db: AsyncSession,
    user: User,
    profile: Profile,
    payload: CampusPositionUpdate,
) -> CampusPosition:
    position = await get_primary_position(db, user.id)
    if position is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No campus position on file')

    _assert_editable(position)
    data = payload.model_dump(exclude_unset=True)
    if 'category' in data and data['category'] not in CAMPUS_CATEGORIES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid campus category')

    for field, value in data.items():
        if isinstance(value, str):
            setattr(position, field, value.strip())
        else:
            setattr(position, field, value)
    position.contact_email = _account_contact_email(user.email)  # keep synced to the account

    _mark_resubmitted(position)

    await db.flush()
    await refresh_profile_completed(db, user, profile)
    await db.commit()
    await db.refresh(position)
    return position
