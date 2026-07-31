"""Employer self-registration (Blueprint Bond Phase 4).

Public and unauthenticated — a prospective employer has no identity in this system yet. Leaves
the organization + contact `pending` with zero access: `EmployerAccount.auth_user_id` stays NULL
until an Honors Admin approves (see `app/features/admin/employers.py`), so a pending/rejected
employer has no Supabase identity at all, not just a gated one.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import EmployerAccount, EmployerOpportunitySubmission, EmployerOrganization


async def register_employer(
    db: AsyncSession, *, organization_name: str, contact_name: str, contact_email: str
) -> EmployerOrganization:
    normalized_email = contact_email.strip().lower()

    existing = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.email == normalized_email))
    ).scalar_one_or_none()
    if existing is not None:
        org = await db.get(EmployerOrganization, existing.organization_id)
        if org is not None and org.status in ('pending', 'approved'):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='An application for this email is already pending or approved',
            )
        if org is not None and org.status == 'rejected':
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='Your previous application was not approved. Contact the school to appeal.',
            )

    org = EmployerOrganization(name=organization_name.strip())
    db.add(org)
    await db.flush()
    db.add(EmployerAccount(organization_id=org.id, email=normalized_email, display_name=contact_name.strip()))
    await db.commit()
    await db.refresh(org)
    return org


async def submit_opportunity(
    db: AsyncSession, *, account: EmployerAccount, payload: OpportunitySubmissionCreate
) -> EmployerOpportunitySubmission:
    submission = EmployerOpportunitySubmission(
        organization_id=account.organization_id,
        submitted_by_id=account.id,
        title=payload.title.strip(),
        description=payload.description.strip(),
        category=payload.category,
        external_url=str(payload.external_url) if payload.external_url else None,
    )
    db.add(submission)
    await db.commit()
    await db.refresh(submission)
    return submission


async def list_my_submissions(
    db: AsyncSession, *, organization_id: UUID, limit: int = 100
) -> list[EmployerOpportunitySubmission]:
    rows = (
        await db.execute(
            select(EmployerOpportunitySubmission)
            .where(EmployerOpportunitySubmission.organization_id == organization_id)
            .order_by(EmployerOpportunitySubmission.created_at.desc())
            .limit(limit)
        )
    ).scalars().all()
    return list(rows)
