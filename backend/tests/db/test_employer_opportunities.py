"""Employer opportunity submission — Blueprint Bond Phase 5 (employer-facing side)."""

from __future__ import annotations

import pytest
from sqlalchemy import select

from app.features.employers import service
from app.features.employers import service as employers_service
from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import CampusPost, EmployerAccount, EmployerOpportunitySubmission


async def _approved_account(db, *, email: str = 'jamie@acme.com', approver=None) -> EmployerAccount:
    org = await service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email=email
    )
    org.status = 'approved'
    # `reviewed_by_id` is what auto-publish attributes the campus post to; without it a
    # submission deliberately stays pending for manual approval.
    if approver is not None:
        org.reviewed_by_id = approver.id
    await db.commit()
    account = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()
    return account


async def test_submit_opportunity_creates_pending_submission(db):
    account = await _approved_account(db)
    payload = OpportunitySubmissionCreate(
        title='Summer Intern', description='Great gig', category='internship', external_url=None
    )
    submission = await service.submit_opportunity(db, account=account, payload=payload)
    assert submission.status == 'pending'
    assert submission.organization_id == account.organization_id
    assert submission.submitted_by_id == account.id


async def test_submission_rejects_invalid_category():
    with pytest.raises(ValueError):
        OpportunitySubmissionCreate(title='X', description='Y', category='not-a-real-category')


async def test_list_my_submissions_scoped_to_organization(db):
    account_a = await _approved_account(db, email='a@acme.com')
    account_b = await _approved_account(db, email='b@beta.com')
    await service.submit_opportunity(
        db, account=account_a, payload=OpportunitySubmissionCreate(title='A role', description='d', category='job')
    )
    await service.submit_opportunity(
        db, account=account_b, payload=OpportunitySubmissionCreate(title='B role', description='d', category='job')
    )

    rows = await service.list_my_submissions(db, organization_id=account_a.organization_id)
    assert len(rows) == 1
    assert rows[0].title == 'A role'


async def test_submission_persists_with_correct_fields(db):
    account = await _approved_account(db)
    payload = OpportunitySubmissionCreate(
        title='Data Analyst', description='Analyze things', category='job',
        external_url='https://acme.com/careers/data-analyst',
    )
    submission = await service.submit_opportunity(db, account=account, payload=payload)
    reloaded = await db.get(EmployerOpportunitySubmission, submission.id)
    assert reloaded.title == 'Data Analyst'
    assert reloaded.external_url == 'https://acme.com/careers/data-analyst'


# ── auto-publish on submit ────────────────────────────────────────────────────────
#
# Policy change: an organisation is vetted once, at approval, so re-reviewing every post it makes
# added admin latency without much added protection. Submissions now publish immediately and
# moderation is reactive (admins archive published posts). The manual approve path still exists
# for anything that could not auto-publish.


async def test_submission_auto_publishes_and_is_visible(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    await db.commit()

    account = await _approved_account(db, approver=admin)
    submission = await service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='Intern', description='Great gig', category='internship'),
    )
    assert submission.status == 'approved'
    assert submission.published_post_id is not None

    post = await db.get(CampusPost, submission.published_post_id)
    assert post.status == 'published'
    assert post.source == 'employer'
    assert post.eligible_program_slug == 'presidential_scholars'
    assert post.kind == 'opportunity'


async def test_auto_publish_without_an_approving_admin_stays_pending(db):
    """Degrades safely rather than guessing an author — an admin can still approve it by hand,
    so the employer's submission is never silently lost."""
    org = await employers_service.register_employer(
        db, organization_name='No Approver Co', contact_name='Sam', contact_email='sam@noapprover.com'
    )
    org.status = 'approved'   # approved, but reviewed_by_id never set (legacy row)
    await db.commit()
    account = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()

    submission = await service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='X', description='Y', category='job'),
    )
    assert submission.status == 'pending'
    assert submission.published_post_id is None


async def test_publish_failure_keeps_the_submission_rather_than_500ing(db, factory, monkeypatch):
    """A publishing outage must never discard what the employer typed."""
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    await db.commit()
    account = await _approved_account(db, approver=admin, email='boom@acme.com')

    async def _boom(*_a, **_kw):
        raise RuntimeError('publishing is down')

    monkeypatch.setattr(service, 'publish_submission', _boom)
    submission = await service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='Kept', description='Not lost', category='job'),
    )
    assert submission.status == 'pending'
    stored = (
        await db.execute(select(EmployerOpportunitySubmission).where(EmployerOpportunitySubmission.title == 'Kept'))
    ).scalar_one()
    assert stored.title == 'Kept'
