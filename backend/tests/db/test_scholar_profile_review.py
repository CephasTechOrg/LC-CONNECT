"""Wave C: Honors review gate before employer discovery."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.admin import scholar_profiles as admin_service
from app.features.employers import discovery
from app.features.scholars import service
from app.features.scholars.schema import ScholarProfessionalProfileUpdate
from app.models import Program, ProgramMembership, ScholarProfessionalProfile
from app.features.scholars.service import MIN_SUMMARY_LENGTH


async def _verified_scholar(db, factory):
    scholar = await factory.user()
    program = (
        await db.execute(select(Program).where(Program.slug == 'presidential_scholars'))
    ).scalar_one_or_none()
    if program is None:
        program = Program(slug='presidential_scholars', name='Presidential Scholars')
        db.add(program)
        await db.flush()
    db.add(ProgramMembership(user_id=scholar.id, program_id=program.id, status='active'))
    await db.commit()
    return scholar


async def _complete_profile(db, scholar_id):
    await service.update_profile(
        db,
        scholar_id,
        ScholarProfessionalProfileUpdate(
            summary='x' * MIN_SUMMARY_LENGTH,
            skills=['Python', 'SQL', 'Leadership'],
            career_interests=['Consulting'],
        ),
    )
    profile = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == scholar_id)
        )
    ).scalar_one()
    profile.headshot_path = 'scholars/u/headshot.jpg'
    profile.resume_path = 'scholars/u/resume.pdf'
    await db.commit()
    await service.set_consent(db, scholar_id, True)


@pytest.mark.asyncio
async def test_consent_alone_is_not_employer_visible(db, factory):
    scholar = await _verified_scholar(db, factory)
    await _complete_profile(db, scholar.id)
    # Still draft until submit + approve
    rows = await discovery.list_eligible_scholars(db)
    assert all(p.user_id != scholar.id for p, _ in rows)


@pytest.mark.asyncio
async def test_submit_approve_makes_employer_visible(db, factory):
    scholar = await _verified_scholar(db, factory)
    admin = await factory.user(display_name='Honors Admin')
    await _complete_profile(db, scholar.id)

    submitted = await service.submit_for_review(db, scholar.id)
    assert submitted.review_status == 'pending_review'

    profile = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == scholar.id)
        )
    ).scalar_one()
    approved = await admin_service.approve_profile(db, actor=admin, profile_id=profile.id)
    assert approved.review_status == 'approved'

    rows = await discovery.list_eligible_scholars(db)
    assert any(p.user_id == scholar.id for p, _ in rows)


@pytest.mark.asyncio
async def test_material_edit_after_approve_leaves_directory(db, factory):
    scholar = await _verified_scholar(db, factory)
    admin = await factory.user(display_name='Honors Admin')
    await _complete_profile(db, scholar.id)
    await service.submit_for_review(db, scholar.id)
    profile = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == scholar.id)
        )
    ).scalar_one()
    await admin_service.approve_profile(db, actor=admin, profile_id=profile.id)

    updated = await service.update_profile(
        db,
        scholar.id,
        ScholarProfessionalProfileUpdate(summary='y' * MIN_SUMMARY_LENGTH),
    )
    assert updated.review_status == 'pending_review'
    rows = await discovery.list_eligible_scholars(db)
    assert all(p.user_id != scholar.id for p, _ in rows)


@pytest.mark.asyncio
async def test_request_changes_and_resubmit(db, factory):
    scholar = await _verified_scholar(db, factory)
    admin = await factory.user(display_name='Honors Admin')
    await _complete_profile(db, scholar.id)
    await service.submit_for_review(db, scholar.id)
    profile = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == scholar.id)
        )
    ).scalar_one()
    changed = await admin_service.request_changes(
        db, actor=admin, profile_id=profile.id, note='Please strengthen the summary.'
    )
    assert changed.review_status == 'changes_requested'
    assert 'strengthen' in (changed.review_note or '')

    resubmitted = await service.submit_for_review(db, scholar.id)
    assert resubmitted.review_status == 'pending_review'
    assert resubmitted.review_note is None


@pytest.mark.asyncio
async def test_submit_incomplete_rejected(db, factory):
    scholar = await _verified_scholar(db, factory)
    with pytest.raises(HTTPException) as exc:
        await service.submit_for_review(db, scholar.id)
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_approve_non_pending_conflicts(db, factory):
    scholar = await _verified_scholar(db, factory)
    admin = await factory.user(display_name='Honors Admin')
    await service.get_my_profile(db, scholar.id)
    profile = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == scholar.id)
        )
    ).scalar_one()
    with pytest.raises(HTTPException) as exc:
        await admin_service.approve_profile(db, actor=admin, profile_id=profile.id)
    assert exc.value.status_code == 409


@pytest.mark.asyncio
async def test_submit_when_already_pending_is_idempotent(db, factory):
    scholar = await _verified_scholar(db, factory)
    await _complete_profile(db, scholar.id)
    first = await service.submit_for_review(db, scholar.id)
    second = await service.submit_for_review(db, scholar.id)
    assert first.review_status == 'pending_review'
    assert second.review_status == 'pending_review'


@pytest.mark.asyncio
async def test_approve_incomplete_pending_rejected(db, factory):
    scholar = await _verified_scholar(db, factory)
    admin = await factory.user(display_name='Honors Admin')
    await service.get_my_profile(db, scholar.id)
    profile = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == scholar.id)
        )
    ).scalar_one()
    # Force into the queue without meeting completeness (admin must still refuse).
    profile.review_status = 'pending_review'
    profile.employer_visibility_consent = True
    await db.commit()
    with pytest.raises(HTTPException) as exc:
        await admin_service.approve_profile(db, actor=admin, profile_id=profile.id)
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_identical_save_does_not_bump_approved(db, factory):
    scholar = await _verified_scholar(db, factory)
    admin = await factory.user(display_name='Honors Admin')
    await _complete_profile(db, scholar.id)
    await service.submit_for_review(db, scholar.id)
    profile = (
        await db.execute(
            select(ScholarProfessionalProfile).where(ScholarProfessionalProfile.user_id == scholar.id)
        )
    ).scalar_one()
    await admin_service.approve_profile(db, actor=admin, profile_id=profile.id)

    # Re-save the same fields — must stay approved (no false re-queue).
    current = await service.get_my_profile(db, scholar.id)
    again = await service.update_profile(
        db,
        scholar.id,
        ScholarProfessionalProfileUpdate(
            summary=current.summary,
            skills=current.skills,
            career_interests=current.career_interests,
            linkedin_url=current.linkedin_url or '',
            handshake_url=current.handshake_url or '',
            internships=current.internships,
            projects=current.projects,
        ),
    )
    assert again.review_status == 'approved'
