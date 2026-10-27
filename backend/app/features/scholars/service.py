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
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.features.scholars.schema import (
    ScholarInternshipEntry,
    ScholarProfessionalProfileRead,
    ScholarProfessionalProfileUpdate,
    ScholarProjectEntry,
)
from app.models import ScholarProfessionalProfile
from app.shared import scholar_profile as _scholar_completeness
from app.shared.blocking import run_image, run_sync
from app.shared.image_processing import sanitize_avatar
from app.shared.programs import PRESIDENTIAL_SCHOLARS_SLUG, is_active_program_member
from app.shared.scholar_profile import missing_profile_fields
from app.shared.storage import storage_service

# Re-export completeness constants so existing
# `from app.features.scholars.service import MIN_SUMMARY_LENGTH` call sites keep working.
CURRENT_CONSENT_VERSION = _scholar_completeness.CURRENT_CONSENT_VERSION
MIN_SUMMARY_LENGTH = _scholar_completeness.MIN_SUMMARY_LENGTH
MIN_SKILLS = _scholar_completeness.MIN_SKILLS
MIN_CAREER_INTERESTS = _scholar_completeness.MIN_CAREER_INTERESTS

MAX_SKILL_LENGTH = 60
MAX_EXPERIENCE_ENTRIES = 5

# Material edits to an approved profile pull it out of the employer directory until Honors
# re-approves. Draft / changes_requested stay put until the scholar submits again.
_STATUSES_REQUIRING_REREVIEW_ON_EDIT = frozenset({'approved'})

_PDF_MAGIC = b'%PDF-'
_ZIP_MAGIC = b'PK\x03\x04'
_DOCX_CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'


async def is_verified_scholar(db: AsyncSession, user_id: UUID) -> bool:
    """Whether this user has an active `presidential_scholars` membership — the single gate
    every professional-profile endpoint enforces."""
    return await is_active_program_member(db, user_id, PRESIDENTIAL_SCHOLARS_SLUG)


def _parse_internships(raw: object) -> list[ScholarInternshipEntry]:
    if not raw:
        return []
    return [ScholarInternshipEntry.model_validate(item) for item in raw]  # type: ignore[arg-type]


def _parse_projects(raw: object) -> list[ScholarProjectEntry]:
    if not raw:
        return []
    return [ScholarProjectEntry.model_validate(item) for item in raw]  # type: ignore[arg-type]


def _to_read(profile: ScholarProfessionalProfile) -> ScholarProfessionalProfileRead:
    missing = missing_profile_fields(profile)
    return ScholarProfessionalProfileRead(
        id=profile.id,
        user_id=profile.user_id,
        linkedin_url=profile.linkedin_url,
        handshake_url=profile.handshake_url,
        summary=profile.summary,
        skills=profile.skills or [],
        career_interests=profile.career_interests or [],
        internships=_parse_internships(profile.internships),
        projects=_parse_projects(profile.projects),
        employer_visibility_consent=profile.employer_visibility_consent,
        consent_given_at=profile.consent_given_at,
        review_status=profile.review_status,  # type: ignore[arg-type]
        review_note=profile.review_note,
        submitted_at=profile.submitted_at,
        reviewed_at=profile.reviewed_at,
        has_headshot=profile.headshot_path is not None,
        has_resume=profile.resume_path is not None,
        created_at=profile.created_at,
        updated_at=profile.updated_at,
        is_complete=not missing,
        missing_fields=missing,
    )


def _requeue_after_material_edit(profile: ScholarProfessionalProfile) -> None:
    """Material change on a live (approved) profile — leave the directory until re-reviewed.

    Incomplete after the edit → `draft` (not the Honors pending queue). Complete → `pending_review`.
    """
    if profile.review_status not in _STATUSES_REQUIRING_REREVIEW_ON_EDIT:
        return
    profile.review_note = None
    if missing_profile_fields(profile):
        profile.review_status = 'draft'
        profile.submitted_at = None
        return
    profile.review_status = 'pending_review'
    profile.submitted_at = datetime.now(UTC)


async def _get_or_create(db: AsyncSession, user_id: UUID) -> ScholarProfessionalProfile:
    """The single choke point every public function below goes through — enforces "verified
    scholar" here in `service.py` (not just the router's `require_verified_scholar` dependency),
    so this can never be bypassed by a future caller that skips the router."""
    if not await is_verified_scholar(db, user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='This feature is only available to verified Presidential Scholars',
        )
    profile = await _load(db, user_id)
    if profile is not None:
        return profile

    # Race-safe, the same arbiter pattern as `ensure_dm_conversation` and message idempotency:
    # `user_id` is UNIQUE, so of two concurrent first-reads only one insert can succeed and the
    # loser reloads the winner's row. This used to be a bare insert, which raised an unhandled
    # `IntegrityError` — surfacing as a 500 to whichever request lost. Reachable in practice
    # because `GET /scholars/me` creates the row lazily, and the mobile client fires several
    # scholar reads concurrently when the dashboard mounts.
    profile = ScholarProfessionalProfile(user_id=user_id)
    db.add(profile)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        winner = await _load(db, user_id)
        if winner is None:  # pragma: no cover — the unique violation guarantees a row exists
            raise
        return winner
    await db.refresh(profile)
    return profile


async def _load(db: AsyncSession, user_id: UUID) -> ScholarProfessionalProfile | None:
    return (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == user_id)
        )
    ).scalar_one_or_none()


async def _locked_profile(db: AsyncSession, user_id: UUID) -> ScholarProfessionalProfile:
    """Load (or create) then row-lock so admin approve/revoke cannot race the requeue decision."""
    profile = await _get_or_create(db, user_id)
    locked = (
        await db.execute(
            select(ScholarProfessionalProfile)
            .where(ScholarProfessionalProfile.id == profile.id)
            .with_for_update()
        )
    ).scalar_one()
    return locked


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
    profile = await _locked_profile(db, user_id)
    material = False
    if payload.linkedin_url is not None:
        new = payload.linkedin_url.strip() or None
        if new != profile.linkedin_url:
            profile.linkedin_url = new
            material = True
    if payload.handshake_url is not None:
        new = payload.handshake_url.strip() or None
        if new != profile.handshake_url:
            profile.handshake_url = new
            material = True
    if payload.summary is not None:
        new = payload.summary.strip() or None
        if new != profile.summary:
            profile.summary = new
            material = True
    skills = _validate_skills(payload.skills)
    if skills is not None and skills != list(profile.skills or []):
        profile.skills = skills
        material = True
    career_interests = _validate_skills(payload.career_interests)
    if career_interests is not None and career_interests != list(profile.career_interests or []):
        profile.career_interests = career_interests
        material = True
    if payload.internships is not None:
        if len(payload.internships) > MAX_EXPERIENCE_ENTRIES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f'At most {MAX_EXPERIENCE_ENTRIES} internships allowed',
            )
        dumped = [entry.model_dump() for entry in payload.internships]
        if dumped != list(profile.internships or []):
            profile.internships = dumped
            material = True
    if payload.projects is not None:
        if len(payload.projects) > MAX_EXPERIENCE_ENTRIES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f'At most {MAX_EXPERIENCE_ENTRIES} projects allowed',
            )
        dumped = [entry.model_dump() for entry in payload.projects]
        if dumped != list(profile.projects or []):
            profile.projects = dumped
            material = True
    if material:
        _requeue_after_material_edit(profile)
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


async def submit_for_review(db: AsyncSession, user_id: UUID) -> ScholarProfessionalProfileRead:
    """Student publishes their completed profile into the Honors review queue.

    Consent + completeness are required; approval is what makes the row employer-visible.
    Idempotent when already `pending_review` (e.g. Save bumped an approved profile, then Submit).
    """
    profile = await _locked_profile(db, user_id)
    missing = missing_profile_fields(profile)
    if missing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f'Profile is incomplete. Still needed: {", ".join(missing)}',
        )
    if profile.review_status == 'pending_review':
        return _to_read(profile)
    if profile.review_status == 'approved':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail='Profile is already approved'
        )
    profile.review_status = 'pending_review'
    profile.submitted_at = datetime.now(UTC)
    profile.review_note = None
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


async def set_consent(db: AsyncSession, user_id: UUID, consent: bool) -> ScholarProfessionalProfileRead:
    """Toggle employer-visibility consent. Revoking it only gates future signed-URL access
    (enforced wherever employer discovery reads it later) — it never deletes the underlying
    résumé/headshot; that's the student's own file, theirs to keep regardless of who can see it."""
    profile = await _locked_profile(db, user_id)
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
    profile = await _locked_profile(db, user_id)
    if len(data) > settings.max_profile_image_mb * 1024 * 1024:
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail='Headshot image is too large'
        )
    clean_data, content_type, ext = await run_image(_validate_headshot, data)
    profile.headshot_path = await run_sync(
        storage_service.upload_scholar_file, user_id, 'headshot', ext, content_type, clean_data
    )
    _requeue_after_material_edit(profile)
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


async def upload_resume(db: AsyncSession, user_id: UUID, data: bytes) -> ScholarProfessionalProfileRead:
    profile = await _locked_profile(db, user_id)
    if len(data) > settings.max_resume_mb * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_CONTENT_TOO_LARGE, detail='Résumé file is too large')
    content_type, ext = _validate_resume(data)
    profile.resume_path = await run_sync(
        storage_service.upload_scholar_file, user_id, 'resume', ext, content_type, data
    )
    _requeue_after_material_edit(profile)
    await db.commit()
    await db.refresh(profile)
    return _to_read(profile)


async def headshot_signed_url(db: AsyncSession, user_id: UUID) -> str:
    profile = await _get_or_create(db, user_id)
    if profile.headshot_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No headshot on file')
    return await run_sync(
        storage_service.scholar_signed_url,
        profile.headshot_path,
        expires_in=settings.scholar_signed_url_expires_seconds,
    )


async def resume_signed_url(db: AsyncSession, user_id: UUID) -> str:
    profile = await _get_or_create(db, user_id)
    if profile.resume_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No résumé on file')
    return await run_sync(
        storage_service.scholar_signed_url,
        profile.resume_path,
        expires_in=settings.scholar_signed_url_expires_seconds,
    )
