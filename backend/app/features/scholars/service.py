"""Blueprint Bond: the scholar's own professional extension (self-service only).

Never touches `ProgramMembership` itself — that's admin-verified (see `app/features/admin/programs.py`).
This module only lets an already-verified scholar complete and manage their own professional profile.
"""

from __future__ import annotations

import zipfile
from datetime import UTC, datetime
from io import BytesIO
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.features.scholars.schema import ScholarProfessionalProfileRead, ScholarProfessionalProfileUpdate
from app.models import Program, ProgramMembership, ScholarProfessionalProfile
from app.shared.image_processing import sanitize_avatar
from app.shared.storage import storage_service

PRESIDENTIAL_SCHOLARS_SLUG = 'presidential_scholars'
CURRENT_CONSENT_VERSION = 1
MAX_SKILL_LENGTH = 60

_PDF_MAGIC = b'%PDF-'
_ZIP_MAGIC = b'PK\x03\x04'
_DOCX_CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'


async def is_verified_scholar(db: AsyncSession, user_id: UUID) -> bool:
    """Whether this user has an active `presidential_scholars` membership — the single gate
    every professional-profile endpoint enforces."""
    row = (
        await db.execute(
            select(ProgramMembership.id)
            .join(Program, Program.id == ProgramMembership.program_id)
            .where(
                ProgramMembership.user_id == user_id,
                ProgramMembership.status == 'active',
                Program.slug == PRESIDENTIAL_SCHOLARS_SLUG,
            )
        )
    ).scalar_one_or_none()
    return row is not None


def _to_read(profile: ScholarProfessionalProfile) -> ScholarProfessionalProfileRead:
    return ScholarProfessionalProfileRead(
        id=profile.id,
        user_id=profile.user_id,
        linkedin_url=profile.linkedin_url,
        handshake_url=profile.handshake_url,
        summary=profile.summary,
        skills=profile.skills,
        career_interests=profile.career_interests,
        employer_visibility_consent=profile.employer_visibility_consent,
        consent_given_at=profile.consent_given_at,
        has_headshot=profile.headshot_path is not None,
        has_resume=profile.resume_path is not None,
        created_at=profile.created_at,
        updated_at=profile.updated_at,
    )


async def _get_or_create(db: AsyncSession, user_id: UUID) -> ScholarProfessionalProfile:
    """The single choke point every public function below goes through — enforces "verified
    scholar" here in `service.py` (not just the router's `require_verified_scholar` dependency),
    so this can never be bypassed by a future caller that skips the router."""
    if not await is_verified_scholar(db, user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='This feature is only available to verified Presidential Scholars',
        )
    profile = (
        await db.execute(select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == user_id))
    ).scalar_one_or_none()
    if profile is not None:
        return profile
    profile = ScholarProfessionalProfile(user_id=user_id)
    db.add(profile)
    await db.commit()
    await db.refresh(profile)
    return profile


async def get_my_profile(db: AsyncSession, user_id: UUID) -> ScholarProfessionalProfileRead:
    return _to_read(await _get_or_create(db, user_id))


def _validate_skills(values: list[str] | None) -> list[str] | None:
    if values is None:
        return None
    cleaned = [v.strip() for v in values if v.strip()]
    for value in cleaned:
        if len(value) > MAX_SKILL_LENGTH:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f'Each entry must be {MAX_SKILL_LENGTH} characters or fewer',
            )
    return cleaned


async def update_profile(
    db: AsyncSession, user_id: UUID, payload: ScholarProfessionalProfileUpdate
) -> ScholarProfessionalProfileRead:
    profile = await _get_or_create(db, user_id)
    if payload.linkedin_url is not None:
        profile.linkedin_url = payload.linkedin_url.strip() or None
    if payload.handshake_url is not None:
        profile.handshake_url = payload.handshake_url.strip() or None
    if payload.summary is not None:
        profile.summary = payload.summary.strip() or None
    skills = _validate_skills(payload.skills)
    if skills is not None:
        profile.skills = skills
    career_interests = _validate_skills(payload.career_interests)
    if career_interests is not None:
        profile.career_interests = career_interests
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


async def set_consent(db: AsyncSession, user_id: UUID, consent: bool) -> ScholarProfessionalProfileRead:
    """Toggle employer-visibility consent. Revoking it only gates future signed-URL access
    (enforced wherever employer discovery reads it later) — it never deletes the underlying
    résumé/headshot; that's the student's own file, theirs to keep regardless of who can see it."""
    profile = await _get_or_create(db, user_id)
    profile.employer_visibility_consent = consent
    if consent:
        profile.consent_given_at = datetime.now(UTC)
        profile.consent_version = CURRENT_CONSENT_VERSION
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


def _validate_headshot(data: bytes) -> tuple[bytes, str, str]:
    """Reuses the same avatar sanitizer as the social profile — real-image validation,
    EXIF/GPS strip, downscale, re-encode to a clean JPEG. Returns (bytes, content_type, ext)."""
    clean_data, content_type = sanitize_avatar(data)
    return clean_data, content_type, 'jpg'


def _validate_resume(data: bytes) -> tuple[str, str]:
    """Sniff the real file signature — never trust the client's content-type header. Returns
    (content_type, ext). Raises 400 for anything that isn't a real PDF or Word document."""
    if data.startswith(_PDF_MAGIC):
        return 'application/pdf', 'pdf'
    if data.startswith(_ZIP_MAGIC):
        try:
            with zipfile.ZipFile(BytesIO(data)) as zf:
                if 'word/document.xml' not in zf.namelist():
                    raise ValueError('not a Word document')
        except (zipfile.BadZipFile, ValueError) as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail='Uploaded file is not a valid résumé document'
            ) from exc
        return _DOCX_CONTENT_TYPE, 'docx'
    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Résumé must be a PDF or Word (.docx) document')


async def upload_headshot(db: AsyncSession, user_id: UUID, data: bytes) -> ScholarProfessionalProfileRead:
    # Authorize before doing any work on the file — a non-scholar gets 403 without us ever
    # decoding their upload.
    profile = await _get_or_create(db, user_id)
    if len(data) > settings.max_profile_image_mb * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail='Headshot image is too large'
        )
    clean_data, content_type, ext = _validate_headshot(data)
    profile.headshot_path = storage_service.upload_scholar_file(user_id, 'headshot', ext, content_type, clean_data)
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


async def upload_resume(db: AsyncSession, user_id: UUID, data: bytes) -> ScholarProfessionalProfileRead:
    profile = await _get_or_create(db, user_id)
    if len(data) > settings.max_resume_mb * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail='Résumé file is too large')
    content_type, ext = _validate_resume(data)
    profile.resume_path = storage_service.upload_scholar_file(user_id, 'resume', ext, content_type, data)
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


async def headshot_signed_url(db: AsyncSession, user_id: UUID) -> str:
    profile = await _get_or_create(db, user_id)
    if profile.headshot_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No headshot on file')
    return storage_service.scholar_signed_url(profile.headshot_path, expires_in=settings.scholar_signed_url_expires_seconds)


async def resume_signed_url(db: AsyncSession, user_id: UUID) -> str:
    profile = await _get_or_create(db, user_id)
    if profile.resume_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No résumé on file')
    return storage_service.scholar_signed_url(profile.resume_path, expires_in=settings.scholar_signed_url_expires_seconds)
