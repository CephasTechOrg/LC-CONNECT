"""Admin dashboard KPI summary — real COUNT(*) aggregates, scope-tailored to the caller."""

from __future__ import annotations

from sqlalchemy import select

from app.features.admin import dashboard as dashboard_admin
from app.features.employers import service as employers_service
from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import (
    AdminMembership,
    CampusPosition,
    CampusPost,
    EmployerAccount,
    Program,
    ProgramMembership,
    Report,
)


async def _admin_with_scope(db, factory, role: str | None):
    admin = await factory.user(display_name=f'{role or "Base"} Admin')
    admin.role = 'admin'
    await db.flush()
    if role is not None:
        db.add(AdminMembership(user_id=admin.id, role=role))
    await db.commit()
    return admin


async def _approved_employer_account(db, *, email: str = 'jamie@acme.com') -> EmployerAccount:
    org = await employers_service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email=email
    )
    org.status = 'approved'
    await db.commit()
    return (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()


async def test_non_honors_admin_gets_only_base_counts(db, factory):
    admin = await _admin_with_scope(db, factory, 'content_admin')
    applicant = await factory.user()
    db.add(Report(reporter_id=admin.id, reason='spam', status='open'))
    db.add(
        CampusPosition(
            user_id=applicant.id,
            category='faculty',
            official_title='Professor',
            department='CS',
            contact_email='prof@livingstone.edu',
            status='pending',
        )
    )
    await db.commit()

    summary = await dashboard_admin.get_dashboard_summary(db, user_id=admin.id)
    assert summary.total_users >= 2
    assert summary.open_reports == 1
    assert summary.pending_positions == 1
    assert summary.active_scholars is None
    assert summary.employer_partners is None
    assert summary.active_opportunities is None
    assert summary.pending_employer_approvals is None
    assert summary.pending_opportunity_reviews is None


async def test_open_reports_excludes_resolved(db, factory):
    admin = await _admin_with_scope(db, factory, None)
    db.add(Report(reporter_id=admin.id, reason='spam', status='open'))
    db.add(Report(reporter_id=admin.id, reason='spam', status='resolved'))
    await db.commit()

    summary = await dashboard_admin.get_dashboard_summary(db, user_id=admin.id)
    assert summary.open_reports == 1


async def test_honors_admin_gets_real_counts(db, factory):
    admin = await _admin_with_scope(db, factory, 'honors_admin')

    # One active + one revoked scholar — only the active one should count.
    program = Program(slug='presidential_scholars', name='Presidential Scholars')
    db.add(program)
    await db.flush()
    active_scholar = await factory.user(display_name='Active Scholar')
    revoked_scholar = await factory.user(display_name='Revoked Scholar')
    db.add(ProgramMembership(user_id=active_scholar.id, program_id=program.id, status='active'))
    db.add(ProgramMembership(user_id=revoked_scholar.id, program_id=program.id, status='revoked'))

    # One approved + one pending employer org — only approved counts toward "employer partners";
    # the pending one counts toward "pending employer approvals".
    await _approved_employer_account(db, email='approved@acme.com')
    await employers_service.register_employer(
        db, organization_name='Still Pending Co', contact_name='Sam', contact_email='sam@pending.com'
    )

    # One published opportunity post + one draft — only published counts.
    db.add(
        CampusPost(
            author_id=admin.id, kind='opportunity', title='Live Role', body='...', status='published'
        )
    )
    db.add(
        CampusPost(author_id=admin.id, kind='opportunity', title='Draft Role', body='...', status='draft')
    )
    await db.commit()

    account = await _approved_employer_account(db, email='submitter@acme.com')
    await employers_service.submit_opportunity(
        db,
        account=account,
        payload=OpportunitySubmissionCreate(
            title='Intern Role', description='Great gig', category='internship'
        ),
    )

    summary = await dashboard_admin.get_dashboard_summary(db, user_id=admin.id)
    assert summary.active_scholars == 1
    assert summary.employer_partners == 2  # both accounts registered via _approved_employer_account
    assert summary.active_opportunities == 1
    assert summary.pending_employer_approvals == 1
    assert summary.pending_opportunity_reviews == 1
