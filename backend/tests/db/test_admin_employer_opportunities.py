"""Honors Admin review of employer opportunity submissions — Blueprint Bond Phase 5.

Covers the publish-through-existing-feed integration, the required-reject-reason rule, and the
retryable/idempotent behavior after a partial publish failure.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.admin import employers as employers_admin
from app.features.campus_hub import content_visibility, publishing
from app.features.employers import service as employers_service
from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import AdminAuditLog, CampusPost, EmployerAccount, ProgramMembership


async def _honors_admin(db, factory):
    from app.models import AdminMembership

    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    await db.flush()
    db.add(AdminMembership(user_id=admin.id, role='honors_admin'))
    await db.commit()
    return admin


async def _approved_account(db, *, email: str = 'jamie@acme.com') -> EmployerAccount:
    org = await employers_service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email=email
    )
    org.status = 'approved'
    await db.commit()
    account = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()
    return account


async def _pending_submission(db, *, email: str = 'jamie@acme.com', category: str = 'internship'):
    account = await _approved_account(db, email=email)
    payload = OpportunitySubmissionCreate(
        title='Summer Intern', description='Great gig', category=category,
        external_url='https://acme.com/careers/intern',
    )
    return await employers_service.submit_opportunity(db, account=account, payload=payload)


async def test_approve_publishes_into_campus_post(db, factory):
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)

    approved = await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)
    assert approved.status == 'approved'
    assert approved.published_post_id is not None

    post = await db.get(CampusPost, approved.published_post_id)
    assert post.kind == 'opportunity'
    assert post.title == 'Summer Intern'
    assert post.source == 'employer'
    assert post.eligible_program_slug == 'presidential_scholars'
    assert post.status == 'published'


async def test_approve_writes_audit_entry(db, factory):
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)
    approved = await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(
                AdminAuditLog.action == 'employer_opportunity_submission.approve',
                AdminAuditLog.target_id == approved.id,
            )
        )
    ).scalar_one()
    assert audit_count == 1


async def test_approve_non_pending_is_409(db, factory):
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)
    await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)

    with pytest.raises(HTTPException) as exc:
        await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)
    assert exc.value.status_code == 409


async def test_reject_requires_reason(db, factory):
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)

    with pytest.raises(HTTPException) as exc:
        await employers_admin.reject_submission(db, actor=admin, submission_id=submission.id, reason='   ')
    assert exc.value.status_code == 400

    # Submission must still be pending — the invalid reject attempt changed nothing.
    await db.refresh(submission)
    assert submission.status == 'pending'


async def test_reject_sets_status_and_note(db, factory):
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)

    rejected = await employers_admin.reject_submission(
        db, actor=admin, submission_id=submission.id, reason='Not relevant to our students'
    )
    assert rejected.status == 'rejected'
    assert rejected.review_note == 'Not relevant to our students'


async def test_reject_non_pending_is_409(db, factory):
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)
    await employers_admin.reject_submission(db, actor=admin, submission_id=submission.id, reason='no')

    with pytest.raises(HTTPException) as exc:
        await employers_admin.reject_submission(db, actor=admin, submission_id=submission.id, reason='no again')
    assert exc.value.status_code == 409


async def test_submission_not_found_404(db, factory):
    admin = await _honors_admin(db, factory)
    with pytest.raises(HTTPException) as exc:
        await employers_admin.approve_submission(db, actor=admin, submission_id=uuid4())
    assert exc.value.status_code == 404


async def test_list_submissions_filters_by_status(db, factory):
    admin = await _honors_admin(db, factory)
    pending = await _pending_submission(db, email='pending@acme.com')
    approved_submission = await _pending_submission(db, email='approved@acme.com')
    await employers_admin.approve_submission(db, actor=admin, submission_id=approved_submission.id)

    pending_rows = await employers_admin.list_submissions(db, status_filter='pending')
    assert [s.id for s, _ in pending_rows] == [pending.id]

    approved_rows = await employers_admin.list_submissions(db, status_filter='approved')
    assert [s.id for s, _ in approved_rows] == [approved_submission.id]


async def test_retry_after_partial_publish_failure_is_idempotent(db, factory, monkeypatch):
    """Simulates `publish_post` failing right after `create_post` committed a draft. A retry must
    reuse that same draft (never publish a second, duplicate post) and finish cleanly."""
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)

    real_publish_post = publishing.publish_post

    async def _failing_publish_post(*args, **kwargs):
        raise RuntimeError('simulated failure')

    monkeypatch.setattr(publishing, 'publish_post', _failing_publish_post)
    with pytest.raises(RuntimeError):
        await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)

    # The draft was created and committed before the simulated failure; the submission itself
    # is untouched (still pending) since we never got to updating it.
    await db.refresh(submission)
    assert submission.status == 'pending'
    draft_count = (
        await db.execute(select(func.count()).select_from(CampusPost).where(CampusPost.title == 'Summer Intern'))
    ).scalar_one()
    assert draft_count == 1  # exactly one draft exists, not zero, not two

    # Retry with the real publish_post restored — must reuse the same post, not create another.
    monkeypatch.setattr(publishing, 'publish_post', real_publish_post)
    approved = await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)
    assert approved.status == 'approved'

    draft_count_after = (
        await db.execute(select(func.count()).select_from(CampusPost).where(CampusPost.title == 'Summer Intern'))
    ).scalar_one()
    assert draft_count_after == 1  # still exactly one — no duplicate was created on retry


async def test_unapproved_submission_never_reaches_the_feed(db, factory):
    await _pending_submission(db)  # never approved, no admin action taken

    student = await factory.user(display_name='Plain Student')
    stmt = content_visibility.published_posts_stmt(user=student)
    posts = (await db.execute(stmt)).scalars().all()
    assert not any(p.title == 'Summer Intern' for p in posts)


async def test_eligibility_filter_enforced_server_side(db, factory):
    """A non-scholar hitting the visibility query directly gets nothing back for a Blueprint
    Bond-eligible post — not just hidden client-side."""
    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)
    approved = await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)
    post = await db.get(CampusPost, approved.published_post_id)

    plain_student = await factory.user(display_name='Plain Student')
    assert await content_visibility.is_post_visible(db, post, user=plain_student) is False

    visible_ids = {
        p.id for p in (await db.execute(content_visibility.published_posts_stmt(user=plain_student))).scalars().all()
    }
    assert post.id not in visible_ids


async def test_verified_scholar_sees_the_eligible_post(db, factory):
    from app.models import Program

    admin = await _honors_admin(db, factory)
    submission = await _pending_submission(db)
    approved = await employers_admin.approve_submission(db, actor=admin, submission_id=submission.id)
    post = await db.get(CampusPost, approved.published_post_id)

    scholar = await factory.user(display_name='Scholar')
    program = Program(slug='presidential_scholars', name='Presidential Scholars')
    db.add(program)
    await db.flush()
    db.add(ProgramMembership(user_id=scholar.id, program_id=program.id, status='active'))
    await db.commit()

    assert await content_visibility.is_post_visible(db, post, user=scholar) is True
    visible_ids = {
        p.id for p in (await db.execute(content_visibility.published_posts_stmt(user=scholar))).scalars().all()
    }
    assert post.id in visible_ids
