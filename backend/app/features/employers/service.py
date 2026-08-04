"""Employer self-registration (Blueprint Bond Phase 4).

Public and unauthenticated — a prospective employer has no identity in this system yet. Leaves
the organization + contact `pending` with zero access: `EmployerAccount.auth_user_id` stays NULL
until an Honors Admin approves (see `app/features/admin/employers.py`), so a pending/rejected
employer has no Supabase identity at all, not just a gated one.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import EmployerAccount, EmployerOpportunitySubmission, EmployerOrganization, User
from app.shared.employer_publishing import publish_submission

logger = logging.getLogger(__name__)


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

    # Auto-publish: the organisation was already vetted when it was approved, so a second review
    # per post added admin latency without much added protection. Moderation is reactive instead
    # — admins can archive any published post. See app/shared/employer_publishing.py.
    org = await db.get(EmployerOrganization, account.organization_id)
    approver = await db.get(User, org.reviewed_by_id) if org and org.reviewed_by_id else None
    if approver is None:
        # No approving admin on record (legacy row, or an org approved before that was tracked).
        # Leave it pending rather than guessing an author — an admin can still approve it by hand,
        # so the employer is never silently stuck with nothing happening.
        logger.warning(
            'Employer opportunity %s left pending: organisation %s has no approving admin to '
            'attribute the post to.', submission.id, account.organization_id,
        )
        return submission

    submission_id = submission.id
    try:
        await publish_submission(db, submission=submission, actor=approver)
    except Exception:  # noqa: BLE001 — a publish failure must not lose the employer's submission
        # The row is already committed above, so it survives as `pending` and an admin can approve
        # it by hand. Better a delayed post than a 500 that discards what they typed.
        logger.exception('Auto-publish failed for employer opportunity %s', submission_id)
        await db.rollback()
        # `rollback()` expires every identity-mapped object, so `submission` can no longer be
        # touched without triggering a lazy refresh (which raises outside the async context).
        # Re-fetch to hand back a clean, attached row.
        return await db.get(EmployerOpportunitySubmission, submission_id)

    submission.status = 'approved'
    submission.reviewed_at = datetime.now(UTC)
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
