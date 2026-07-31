"""Blueprint Bond Phase 2 — scholar professional profile self-service."""

from __future__ import annotations

import io

import pytest
from fastapi import HTTPException
from PIL import Image
from sqlalchemy import select

from app.features.scholars import service
from app.features.scholars.schema import ScholarProfessionalProfileUpdate
from app.models import Program, ProgramMembership, User


def _jpeg(size=(50, 50), color='blue') -> bytes:
    img = Image.new('RGB', size, color)
    buf = io.BytesIO()
    img.save(buf, 'JPEG')
    return buf.getvalue()


_FAKE_PDF = b'%PDF-1.4\n%fake resume for tests\n%%EOF'


async def _verified_scholar(db, factory) -> User:
    student = await factory.user(display_name='Scholar')
    program = Program(slug=service.PRESIDENTIAL_SCHOLARS_SLUG, name='Presidential Scholars')
    db.add(program)
    await db.flush()
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()
    return student


# ── is_verified_scholar ─────────────────────────────────────────────────────────


async def test_is_verified_scholar_false_for_plain_student(db, factory):
    student = await factory.user(display_name='Plain Student')
    assert await service.is_verified_scholar(db, student.id) is False


async def test_is_verified_scholar_true_after_verification(db, factory):
    scholar = await _verified_scholar(db, factory)
    assert await service.is_verified_scholar(db, scholar.id) is True


async def test_is_verified_scholar_false_after_revoke(db, factory):
    scholar = await _verified_scholar(db, factory)
    membership = (
        await db.execute(select(ProgramMembership).where(ProgramMembership.user_id == scholar.id))
    ).scalar_one()
    membership.status = 'revoked'
    await db.commit()
    assert await service.is_verified_scholar(db, scholar.id) is False


# ── authorization: every public function 403s a non-scholar ────────────────────


async def test_non_scholar_gets_403_on_every_endpoint(db, factory):
    student = await factory.user(display_name='Plain Student')

    for coro in (
        service.get_my_profile(db, student.id),
        service.update_profile(db, student.id, ScholarProfessionalProfileUpdate()),
        service.set_consent(db, student.id, True),
        service.upload_headshot(db, student.id, _jpeg()),
        service.upload_resume(db, student.id, _FAKE_PDF),
        service.headshot_signed_url(db, student.id),
        service.resume_signed_url(db, student.id),
    ):
        with pytest.raises(HTTPException) as exc:
            await coro
        assert exc.value.status_code == 403


# ── get_my_profile / update_profile ─────────────────────────────────────────────


async def test_get_my_profile_auto_creates_empty_profile(db, factory):
    scholar = await _verified_scholar(db, factory)
    profile = await service.get_my_profile(db, scholar.id)
    assert profile.linkedin_url is None
    assert profile.skills == []
    assert profile.employer_visibility_consent is False
    assert profile.has_headshot is False
    assert profile.has_resume is False


async def test_update_profile_sets_fields(db, factory):
    scholar = await _verified_scholar(db, factory)
    updated = await service.update_profile(
        db,
        scholar.id,
        ScholarProfessionalProfileUpdate(
            linkedin_url='https://linkedin.com/in/scholar',
            summary='A dedicated student leader.',
            skills=['Python', 'Public Speaking'],
            career_interests=['Consulting'],
        ),
    )
    assert updated.linkedin_url == 'https://linkedin.com/in/scholar'
    assert updated.summary == 'A dedicated student leader.'
    assert updated.skills == ['Python', 'Public Speaking']
    assert updated.career_interests == ['Consulting']


async def test_update_profile_rejects_overlong_skill(db, factory):
    scholar = await _verified_scholar(db, factory)
    with pytest.raises(HTTPException) as exc:
        await service.update_profile(
            db, scholar.id, ScholarProfessionalProfileUpdate(skills=['x' * 61])
        )
    assert exc.value.status_code == 400


# ── consent ──────────────────────────────────────────────────────────────────────


async def test_set_consent_true_stamps_timestamp_and_version(db, factory):
    scholar = await _verified_scholar(db, factory)
    updated = await service.set_consent(db, scholar.id, True)
    assert updated.employer_visibility_consent is True
    assert updated.consent_given_at is not None


async def test_set_consent_false_clears_flag_but_keeps_files(db, factory):
    scholar = await _verified_scholar(db, factory)
    await service.set_consent(db, scholar.id, True)
    updated = await service.set_consent(db, scholar.id, False)
    assert updated.employer_visibility_consent is False


# ── headshot / résumé validation (no storage configured in tests) ──────────────


async def test_upload_headshot_rejects_non_image(db, factory):
    scholar = await _verified_scholar(db, factory)
    with pytest.raises(HTTPException) as exc:
        await service.upload_headshot(db, scholar.id, b'not an image')
    assert exc.value.status_code == 400


async def test_upload_headshot_rejects_oversized_file(db, factory, monkeypatch):
    scholar = await _verified_scholar(db, factory)
    monkeypatch.setattr(service.settings, 'max_profile_image_mb', 0)
    with pytest.raises(HTTPException) as exc:
        await service.upload_headshot(db, scholar.id, _jpeg())
    assert exc.value.status_code == 413


async def test_upload_resume_rejects_wrong_type(db, factory):
    scholar = await _verified_scholar(db, factory)
    with pytest.raises(HTTPException) as exc:
        await service.upload_resume(db, scholar.id, b'plain text, not a resume')
    assert exc.value.status_code == 400


async def test_upload_resume_rejects_oversized_file(db, factory, monkeypatch):
    scholar = await _verified_scholar(db, factory)
    monkeypatch.setattr(service.settings, 'max_resume_mb', 0)
    with pytest.raises(HTTPException) as exc:
        await service.upload_resume(db, scholar.id, _FAKE_PDF)
    assert exc.value.status_code == 413


async def test_upload_headshot_503_when_storage_unconfigured(db, factory, monkeypatch):
    scholar = await _verified_scholar(db, factory)
    monkeypatch.setattr(service.storage_service, 'client', None)
    with pytest.raises(HTTPException) as exc:
        await service.upload_headshot(db, scholar.id, _jpeg())
    assert exc.value.status_code == 503


# ── successful upload (storage mocked) ──────────────────────────────────────────


async def test_upload_headshot_success_sets_path(db, factory, monkeypatch):
    scholar = await _verified_scholar(db, factory)
    monkeypatch.setattr(
        service.storage_service, 'upload_scholar_file', lambda *a, **kw: f'{scholar.id}/headshot.jpg'
    )
    updated = await service.upload_headshot(db, scholar.id, _jpeg())
    assert updated.has_headshot is True


async def test_upload_resume_success_sets_path(db, factory, monkeypatch):
    scholar = await _verified_scholar(db, factory)
    monkeypatch.setattr(
        service.storage_service, 'upload_scholar_file', lambda *a, **kw: f'{scholar.id}/resume.pdf'
    )
    updated = await service.upload_resume(db, scholar.id, _FAKE_PDF)
    assert updated.has_resume is True


async def test_signed_url_404_when_no_file_uploaded(db, factory):
    scholar = await _verified_scholar(db, factory)
    with pytest.raises(HTTPException) as exc:
        await service.headshot_signed_url(db, scholar.id)
    assert exc.value.status_code == 404


async def test_signed_url_success(db, factory, monkeypatch):
    scholar = await _verified_scholar(db, factory)
    monkeypatch.setattr(
        service.storage_service, 'upload_scholar_file', lambda *a, **kw: f'{scholar.id}/headshot.jpg'
    )
    await service.upload_headshot(db, scholar.id, _jpeg())
    monkeypatch.setattr(
        service.storage_service, 'scholar_signed_url', lambda *a, **kw: 'https://example.com/signed'
    )
    url = await service.headshot_signed_url(db, scholar.id)
    assert url == 'https://example.com/signed'
