"""Approved-employer scholar discovery (Blueprint Bond Phase 6).

Every read here re-evaluates eligibility live — active `presidential_scholars` membership AND
current `employer_visibility_consent = true` — rather than trusting anything cached. Revoking
consent (or losing scholar status) removes a scholar from discovery immediately, on the very next
request; there is no separate "sync" step that could lag behind.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import EmployerProfileView, Profile, Program, ProgramMembership, ScholarProfessionalProfile
from app.shared.programs import PRESIDENTIAL_SCHOLARS_SLUG
from app.shared.storage import storage_service


def _eligible_scholars_stmt():
    return (
        select(ScholarProfessionalProfile, Profile)
        .join(Profile, Profile.user_id == ScholarProfessionalProfile.user_id)
        .join(ProgramMembership, ProgramMembership.user_id == ScholarProfessionalProfile.user_id)
        .join(Program, Program.id == ProgramMembership.program_id)
        .where(
            ScholarProfessionalProfile.employer_visibility_consent.is_(True),
            ProgramMembership.status == 'active',
            Program.slug == PRESIDENTIAL_SCHOLARS_SLUG,
        )
    )


async def list_eligible_scholars(db: AsyncSession, *, limit: int = 50) -> list[tuple[ScholarProfessionalProfile, Profile]]:
    rows = (
        await db.execute(_eligible_scholars_stmt().order_by(Profile.display_name.asc()).limit(limit))
    ).all()
    return list(rows)


async def get_eligible_scholar_or_404(
    db: AsyncSession, user_id: UUID
) -> tuple[ScholarProfessionalProfile, Profile]:
    row = (
        await db.execute(_eligible_scholars_stmt().where(ScholarProfessionalProfile.user_id == user_id))
    ).one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Scholar not found')
    return row


async def record_view(db: AsyncSession, *, employer_account_id: UUID, scholar_user_id: UUID) -> None:
    db.add(EmployerProfileView(employer_account_id=employer_account_id, scholar_user_id=scholar_user_id))
    await db.commit()


async def headshot_signed_url(db: AsyncSession, user_id: UUID) -> str:
    profile, _ = await get_eligible_scholar_or_404(db, user_id)
    if profile.headshot_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No headshot on file')
    return storage_service.scholar_signed_url(
        profile.headshot_path, expires_in=settings.scholar_signed_url_expires_seconds
    )


async def resume_signed_url(db: AsyncSession, user_id: UUID) -> str:
    profile, _ = await get_eligible_scholar_or_404(db, user_id)
    if profile.resume_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No résumé on file')
    return storage_service.scholar_signed_url(
        profile.resume_path, expires_in=settings.scholar_signed_url_expires_seconds
    )
