"""Employer opportunity submission — Blueprint Bond Phase 5 (employer-facing side)."""

from __future__ import annotations

import pytest
from sqlalchemy import select

from app.features.employers import service
from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import EmployerAccount, EmployerOpportunitySubmission


async def _approved_account(db, *, email: str = 'jamie@acme.com') -> EmployerAccount:
    org = await service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email=email
    )
    org.status = 'approved'
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
