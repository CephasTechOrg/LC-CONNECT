"""Approved-employer scholar discovery — Blueprint Bond Phase 6.

Covers live (never cached) eligibility re-checks and the strict employer-view allowlist.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.employers import discovery
from app.features.employers import service as employers_service
from app.features.employers.router import _scholar_view
from app.features.employers.schema import EmployerScholarView
from app.models import EmployerAccount, EmployerProfileView, Program, ProgramMembership, ScholarProfessionalProfile


async def _approved_employer_account(db, *, email: str = 'jamie@acme.com') -> EmployerAccount:
    org = await employers_service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email=email
    )
    org.status = 'approved'
    await db.commit()
    return (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()


async def _eligible_scholar(db, factory, *, display_name: str = 'Scholar', consent: bool = True):
    scholar = await factory.user(display_name=display_name)
    program = (
        await db.execute(select(Program).where(Program.slug == 'presidential_scholars'))
    ).scalar_one_or_none()
    if program is None:
        program = Program(slug='presidential_scholars', name='Presidential Scholars')
        db.add(program)
        await db.flush()
    db.add(ProgramMembership(user_id=scholar.id, program_id=program.id, status='active'))
    profile = ScholarProfessionalProfile(
        user_id=scholar.id,
        employer_visibility_consent=consent,
        linkedin_url='https://linkedin.com/in/scholar',
        summary='A dedicated student leader.',
        skills=['Python'],
        career_interests=['Consulting'],
    )
    db.add(profile)
    await db.commit()
    return scholar, profile


# ── list_eligible_scholars / get_eligible_scholar_or_404 ────────────────────────────


async def test_list_excludes_non_consenting_scholar(db, factory):
    await _eligible_scholar(db, factory, display_name='Consents', consent=True)
    await _eligible_scholar(db, factory, display_name='No Consent', consent=False)

    rows = await discovery.list_eligible_scholars(db)
    names = {social.display_name for _, social in rows}
    assert names == {'Consents'}


async def test_list_excludes_plain_student(db, factory):
    await factory.user(display_name='Plain Student')
    await _eligible_scholar(db, factory, display_name='Eligible')

    rows = await discovery.list_eligible_scholars(db)
    names = {social.display_name for _, social in rows}
    assert names == {'Eligible'}


async def test_list_excludes_revoked_membership(db, factory):
    scholar, _ = await _eligible_scholar(db, factory, display_name='Revoked')
    membership = (
        await db.execute(select(ProgramMembership).where(ProgramMembership.user_id == scholar.id))
    ).scalar_one()
    membership.status = 'revoked'
    await db.commit()

    rows = await discovery.list_eligible_scholars(db)
    assert rows == []


async def test_get_eligible_scholar_returns_for_eligible(db, factory):
    scholar, _ = await _eligible_scholar(db, factory)
    profile, social = await discovery.get_eligible_scholar_or_404(db, scholar.id)
    assert profile.user_id == scholar.id
    assert social.user_id == scholar.id


async def test_get_eligible_scholar_404_for_non_consenting(db, factory):
    scholar, _ = await _eligible_scholar(db, factory, consent=False)
    with pytest.raises(HTTPException) as exc:
        await discovery.get_eligible_scholar_or_404(db, scholar.id)
    assert exc.value.status_code == 404


async def test_get_eligible_scholar_404_for_unknown_user(db):
    with pytest.raises(HTTPException) as exc:
        await discovery.get_eligible_scholar_or_404(db, uuid4())
    assert exc.value.status_code == 404


async def test_revoking_consent_immediately_removes_from_discovery(db, factory):
    """No caching/staleness — the very next read reflects the change."""
    scholar, profile = await _eligible_scholar(db, factory)
    # Confirm visible first.
    await discovery.get_eligible_scholar_or_404(db, scholar.id)

    profile.employer_visibility_consent = False
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await discovery.get_eligible_scholar_or_404(db, scholar.id)
    assert exc.value.status_code == 404

    rows = await discovery.list_eligible_scholars(db)
    assert scholar.id not in {p.user_id for p, _ in rows}


async def test_revoking_membership_immediately_removes_from_discovery(db, factory):
    scholar, _ = await _eligible_scholar(db, factory)
    await discovery.get_eligible_scholar_or_404(db, scholar.id)

    membership = (
        await db.execute(select(ProgramMembership).where(ProgramMembership.user_id == scholar.id))
    ).scalar_one()
    membership.status = 'revoked'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await discovery.get_eligible_scholar_or_404(db, scholar.id)
    assert exc.value.status_code == 404


# ── record_view (audit trail) ────────────────────────────────────────────────────


async def test_record_view_writes_audit_row(db, factory):
    scholar, _ = await _eligible_scholar(db, factory)
    account = await _approved_employer_account(db)
    await discovery.record_view(db, employer_account_id=account.id, scholar_user_id=scholar.id)

    count = (
        await db.execute(
            select(func.count())
            .select_from(EmployerProfileView)
            .where(EmployerProfileView.scholar_user_id == scholar.id)
        )
    ).scalar_one()
    assert count == 1


# ── signed URLs ───────────────────────────────────────────────────────────────────


async def test_headshot_signed_url_404_without_headshot(db, factory):
    scholar, _ = await _eligible_scholar(db, factory)
    with pytest.raises(HTTPException) as exc:
        await discovery.headshot_signed_url(db, scholar.id)
    assert exc.value.status_code == 404


async def test_headshot_signed_url_success(db, factory, monkeypatch):
    scholar, profile = await _eligible_scholar(db, factory)
    profile.headshot_path = f'{scholar.id}/headshot.jpg'
    await db.commit()
    monkeypatch.setattr(discovery.storage_service, 'scholar_signed_url', lambda *a, **kw: 'https://example.com/signed')

    url = await discovery.headshot_signed_url(db, scholar.id)
    assert url == 'https://example.com/signed'


async def test_signed_url_404_for_non_consenting_scholar_even_with_headshot(db, factory):
    """Revoked consent blocks signed-URL issuance too, not just the profile view."""
    scholar, profile = await _eligible_scholar(db, factory, consent=False)
    profile.headshot_path = f'{scholar.id}/headshot.jpg'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await discovery.headshot_signed_url(db, scholar.id)
    assert exc.value.status_code == 404


async def test_resume_signed_url_404_without_resume(db, factory):
    scholar, _ = await _eligible_scholar(db, factory)
    with pytest.raises(HTTPException) as exc:
        await discovery.resume_signed_url(db, scholar.id)
    assert exc.value.status_code == 404


async def test_resume_signed_url_success(db, factory, monkeypatch):
    scholar, profile = await _eligible_scholar(db, factory)
    profile.resume_path = f'{scholar.id}/resume.pdf'
    await db.commit()
    monkeypatch.setattr(discovery.storage_service, 'scholar_signed_url', lambda *a, **kw: 'https://example.com/signed')

    url = await discovery.resume_signed_url(db, scholar.id)
    assert url == 'https://example.com/signed'


async def test_resume_signed_url_404_for_non_consenting_scholar_even_with_resume(db, factory):
    """Revoked consent blocks signed-URL issuance too, not just the profile view."""
    scholar, profile = await _eligible_scholar(db, factory, consent=False)
    profile.resume_path = f'{scholar.id}/resume.pdf'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await discovery.resume_signed_url(db, scholar.id)
    assert exc.value.status_code == 404


# ── EmployerScholarView allowlist ──────────────────────────────────────────────────


def test_employer_scholar_view_field_allowlist():
    """Locks the exact field set — a future addition to Profile/User must never silently appear
    here. If this test needs updating, that's a deliberate, reviewed expansion of what employers
    can see, not an accident."""
    assert set(EmployerScholarView.model_fields.keys()) == {
        'user_id',
        'display_name',
        'linkedin_url',
        'handshake_url',
        'summary',
        'skills',
        'career_interests',
        'has_headshot',
        'has_resume',
        # Reviewed addition: a short-lived signed headshot URL so the portal renders the face
        # inline. Exposes nothing an approved employer couldn't already fetch via the dedicated
        # headshot-url endpoint — it only saves a round trip.
        'headshot_url',
    }
    forbidden = {'bio', 'major', 'class_year', 'avatar_url', 'interests', 'pronouns', 'country_state', 'campus'}
    assert forbidden.isdisjoint(EmployerScholarView.model_fields.keys())


async def test_scholar_view_helper_builds_only_allowlisted_fields(db, factory):
    scholar, profile = await _eligible_scholar(db, factory)
    _, social = await discovery.get_eligible_scholar_or_404(db, scholar.id)

    view = _scholar_view(profile, social)
    assert view.user_id == scholar.id
    assert view.display_name == social.display_name
    assert view.linkedin_url == profile.linkedin_url
    assert view.summary == profile.summary
    assert view.skills == profile.skills
    assert view.career_interests == profile.career_interests
    assert view.has_headshot is False
    assert view.has_resume is False
