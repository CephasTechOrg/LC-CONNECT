"""Honors Admin review queue for Blueprint Bond professional profiles (Wave C).

Employer discovery requires `review_status == approved` in addition to consent + membership.
This module is the only place that transitions pending → approved / changes_requested / revoked.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Profile, ScholarProfessionalProfile, User
from app.shared.audit import record_audit
from app.shared.scholar_profile import REVIEW_STATUSES, missing_profile_fields


def _snapshot(profile: ScholarProfessionalProfile) -> dict[str, str | None]:
    return {
        'review_status': profile.review_status,
        'review_note': profile.review_note,
    }


async def _locked_profile(db: AsyncSession, profile_id: UUID) -> ScholarProfessionalProfile:
    profile = (
        await db.execute(
            select(ScholarProfessionalProfile)
            .where(ScholarProfessionalProfile.id == profile_id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Scholar profile not found')
    return profile


async def list_profiles(
    db: AsyncSession, *, status_filter: str = 'pending_review', limit: int = 200
) -> list[tuple[ScholarProfessionalProfile, User, Profile]]:
    if status_filter not in REVIEW_STATUSES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f'Invalid status. Expected one of: {", ".join(sorted(REVIEW_STATUSES))}',
        )
    rows = (
        await db.execute(
            select(ScholarProfessionalProfile, User, Profile)
            .join(User, User.id == ScholarProfessionalProfile.user_id)
            .join(Profile, Profile.user_id == User.id)
            .where(ScholarProfessionalProfile.review_status == status_filter)
            .order_by(ScholarProfessionalProfile.submitted_at.asc().nulls_last())
            .limit(limit)
        )
    ).all()
    return list(rows)


async def approve_profile(
    db: AsyncSession, *, actor: User, profile_id: UUID
) -> ScholarProfessionalProfile:
    profile = await _locked_profile(db, profile_id)
    if profile.review_status != 'pending_review':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Only a profile awaiting review can be approved',
        )
    missing = missing_profile_fields(profile)
    if missing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f'Cannot approve an incomplete profile. Still needed: {", ".join(missing)}',
        )
    before = _snapshot(profile)
    profile.review_status = 'approved'
    profile.review_note = None
    profile.reviewed_by_id = actor.id
    profile.reviewed_at = datetime.now(UTC)
    await record_audit(
        db,
        actor_id=actor.id,
        action='scholar_professional_profile.approve',
        target_type='scholar_professional_profile',
        target_id=profile.id,
        before_data=before,
        after_data=_snapshot(profile),
    )
    await db.commit()
    await db.refresh(profile)
    return profile


async def request_changes(
    db: AsyncSession, *, actor: User, profile_id: UUID, note: str
) -> ScholarProfessionalProfile:
    profile = await _locked_profile(db, profile_id)
    if profile.review_status != 'pending_review':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Only a profile awaiting review can be sent back for changes',
        )
    cleaned = note.strip()
    if not cleaned:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='A review note is required')
    before = _snapshot(profile)
    profile.review_status = 'changes_requested'
    profile.review_note = cleaned
    profile.reviewed_by_id = actor.id
    profile.reviewed_at = datetime.now(UTC)
    await record_audit(
        db,
        actor_id=actor.id,
        action='scholar_professional_profile.request_changes',
        target_type='scholar_professional_profile',
        target_id=profile.id,
        before_data=before,
        after_data=_snapshot(profile),
    )
    await db.commit()
    await db.refresh(profile)
    return profile


async def revoke_profile(
    db: AsyncSession, *, actor: User, profile_id: UUID, note: str | None = None
) -> ScholarProfessionalProfile:
    profile = await _locked_profile(db, profile_id)
    if profile.review_status != 'approved':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Only an approved profile can be revoked from employer visibility',
        )
    before = _snapshot(profile)
    profile.review_status = 'revoked'
    profile.review_note = (note or '').strip() or None
    profile.reviewed_by_id = actor.id
    profile.reviewed_at = datetime.now(UTC)
    await record_audit(
        db,
        actor_id=actor.id,
        action='scholar_professional_profile.revoke',
        target_type='scholar_professional_profile',
        target_id=profile.id,
        before_data=before,
        after_data=_snapshot(profile),
    )
    await db.commit()
    await db.refresh(profile)
    return profile
