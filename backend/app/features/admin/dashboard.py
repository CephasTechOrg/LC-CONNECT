"""Aggregate counts for the admin dashboard's KPI cards.

Real `COUNT(*)` queries, never a capped list endpoint's `.length` — `/admin/users` caps at 200 for
the roster view, which would silently undercount the true total once the platform grows past that.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.admin.admins import get_admin_scopes
from app.features.admin.schema import AdminDashboardSummary
from app.models import (
    CampusPosition,
    CampusPost,
    EmployerOpportunitySubmission,
    EmployerOrganization,
    Program,
    ProgramMembership,
    Report,
    User,
)
from app.shared.programs import PRESIDENTIAL_SCHOLARS_SLUG


async def _scalar_count(db: AsyncSession, stmt) -> int:
    return (await db.execute(stmt)).scalar_one()


async def get_dashboard_summary(db: AsyncSession, *, user_id: UUID) -> AdminDashboardSummary:
    """`total_users`/`open_reports` are base-admin facts, shown to every admin. The Honors-Program
    counts are only meaningful to someone who can act on them (the Scholars/Employers pages are
    already `honors_admin`-gated) — a non-Honors admin gets `null` for those fields rather than a
    fabricated 0, so the dashboard never implies "zero employer partners" when the truth is
    "you can't see this."""
    scopes = await get_admin_scopes(db, user_id)
    is_honors = 'honors_admin' in scopes

    total_users = await _scalar_count(db, select(func.count(User.id)))
    open_reports = await _scalar_count(db, select(func.count(Report.id)).where(Report.status == 'open'))
    pending_positions = await _scalar_count(
        db, select(func.count(CampusPosition.id)).where(CampusPosition.status == 'pending')
    )

    active_scholars = employer_partners = active_opportunities = None
    pending_employer_approvals = pending_opportunity_reviews = None

    if is_honors:
        active_scholars = await _scalar_count(
            db,
            select(func.count(ProgramMembership.id))
            .join(Program, Program.id == ProgramMembership.program_id)
            .where(Program.slug == PRESIDENTIAL_SCHOLARS_SLUG, ProgramMembership.status == 'active'),
        )
        employer_partners = await _scalar_count(
            db, select(func.count(EmployerOrganization.id)).where(EmployerOrganization.status == 'approved')
        )
        active_opportunities = await _scalar_count(
            db,
            select(func.count(CampusPost.id)).where(CampusPost.kind == 'opportunity', CampusPost.status == 'published'),
        )
        pending_employer_approvals = await _scalar_count(
            db, select(func.count(EmployerOrganization.id)).where(EmployerOrganization.status == 'pending')
        )
        pending_opportunity_reviews = await _scalar_count(
            db,
            select(func.count(EmployerOpportunitySubmission.id)).where(EmployerOpportunitySubmission.status == 'pending'),
        )

    return AdminDashboardSummary(
        total_users=total_users,
        open_reports=open_reports,
        pending_positions=pending_positions,
        active_scholars=active_scholars,
        employer_partners=employer_partners,
        active_opportunities=active_opportunities,
        pending_employer_approvals=pending_employer_approvals,
        pending_opportunity_reviews=pending_opportunity_reviews,
    )
