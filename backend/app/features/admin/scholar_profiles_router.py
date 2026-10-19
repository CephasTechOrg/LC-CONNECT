"""Honors Admin Blueprint Bond profile review endpoints (`/admin/scholar-profiles/...`).

Kept out of `admin/router.py` for the line-cap — same pattern as `admins_router`.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.email_notices import send_quietly, send_scholar_profile_decision_email
from app.features.admin import admins as admins_admin
from app.features.admin import scholar_profiles as scholar_profiles_admin
from app.features.admin.schema import (
    ScholarProfileAdminRead,
    ScholarProfileReviewNoteRequest,
    ScholarProfileRevokeRequest,
)
from app.features.realtime.runtime import emit_notification
from app.models import Profile, ScholarProfessionalProfile, User

router = APIRouter()


async def _notify_scholar_decision(
    *,
    user_id: UUID,
    email: str,
    profile_id: UUID,
    outcome: str,
    review_note: str | None,
) -> None:
    """In-app + push, then email (notes travel in mail; notification.detail is emoji-sized)."""
    await emit_notification(
        user_id=user_id,
        notif_type=f'scholar_profile_{outcome}',
        target_type='scholar_profile',
        target_id=profile_id,
    )
    send_quietly(
        send_scholar_profile_decision_email,
        email,
        outcome=outcome,
        review_note=review_note,
    )


def _admin_read(profile: ScholarProfessionalProfile, user: User, social: Profile) -> ScholarProfileAdminRead:
    return ScholarProfileAdminRead(
        id=profile.id,
        user_id=profile.user_id,
        user_email=user.email,
        display_name=social.display_name,
        summary=profile.summary,
        skills=list(profile.skills or []),
        career_interests=list(profile.career_interests or []),
        internships=list(profile.internships or []),
        projects=list(profile.projects or []),
        linkedin_url=profile.linkedin_url,
        handshake_url=profile.handshake_url,
        has_headshot=profile.headshot_path is not None,
        has_resume=profile.resume_path is not None,
        employer_visibility_consent=profile.employer_visibility_consent,
        review_status=profile.review_status,
        review_note=profile.review_note,
        submitted_at=profile.submitted_at,
        reviewed_at=profile.reviewed_at,
        updated_at=profile.updated_at,
    )


async def _user_and_profile(db: AsyncSession, user_id: UUID) -> tuple[User, Profile]:
    user = await db.get(User, user_id)
    social = (
        await db.execute(select(Profile).where(Profile.user_id == user_id))
    ).scalar_one_or_none()
    if user is None or social is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Scholar not found')
    return user, social


@router.get('/scholar-profiles', response_model=list[ScholarProfileAdminRead])
async def list_scholar_profiles(
    status: str = Query(default='pending_review'),
    _: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> list[ScholarProfileAdminRead]:
    rows = await scholar_profiles_admin.list_profiles(db, status_filter=status)
    return [_admin_read(profile, user, social) for profile, user, social in rows]


@router.post('/scholar-profiles/{profile_id}/approve', response_model=ScholarProfileAdminRead)
async def approve_scholar_profile(
    profile_id: UUID,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfileAdminRead:
    profile = await scholar_profiles_admin.approve_profile(db, actor=actor, profile_id=profile_id)
    user, social = await _user_and_profile(db, profile.user_id)
    await _notify_scholar_decision(
        user_id=profile.user_id,
        email=user.email,
        profile_id=profile.id,
        outcome='approved',
        review_note=None,
    )
    return _admin_read(profile, user, social)


@router.post('/scholar-profiles/{profile_id}/request-changes', response_model=ScholarProfileAdminRead)
async def request_scholar_profile_changes(
    profile_id: UUID,
    payload: ScholarProfileReviewNoteRequest,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfileAdminRead:
    profile = await scholar_profiles_admin.request_changes(
        db, actor=actor, profile_id=profile_id, note=payload.reason
    )
    user, social = await _user_and_profile(db, profile.user_id)
    await _notify_scholar_decision(
        user_id=profile.user_id,
        email=user.email,
        profile_id=profile.id,
        outcome='changes_requested',
        review_note=profile.review_note,
    )
    return _admin_read(profile, user, social)


@router.post('/scholar-profiles/{profile_id}/revoke', response_model=ScholarProfileAdminRead)
async def revoke_scholar_profile(
    profile_id: UUID,
    payload: ScholarProfileRevokeRequest | None = None,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfileAdminRead:
    note = payload.reason if payload is not None else None
    profile = await scholar_profiles_admin.revoke_profile(db, actor=actor, profile_id=profile_id, note=note)
    user, social = await _user_and_profile(db, profile.user_id)
    await _notify_scholar_decision(
        user_id=profile.user_id,
        email=user.email,
        profile_id=profile.id,
        outcome='revoked',
        review_note=profile.review_note,
    )
    return _admin_read(profile, user, social)
