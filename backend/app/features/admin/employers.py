"""Honors Admin approval queue for employer organizations (Blueprint Bond Phase 4).

Approval is the moment an employer contact goes from "no Supabase identity at all" to invited —
the exact same `invite_auth_user` path Phase 3 uses for admins, so approving an employer means
they get a real invite email to set their own password (never an admin-set one).
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import EmployerAccount, EmployerOpportunitySubmission, EmployerOrganization, User
from app.shared.audit import record_audit
from app.shared.employer_publishing import publish_submission
from app.shared.supabase_admin import (
    AuthUserAlreadyRegistered,
    get_auth_user_id_by_email,
    invite_auth_user,
)


def _org_snapshot(org: EmployerOrganization) -> dict[str, str | None]:
    return {'status': org.status, 'review_note': org.review_note}


async def get_organization_or_404(db: AsyncSession, org_id: UUID) -> EmployerOrganization:
    org = await db.get(EmployerOrganization, org_id)
    if org is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Employer organization not found')
    return org


async def get_account_for_org(db: AsyncSession, org_id: UUID) -> EmployerAccount:
    account = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org_id))
    ).scalar_one()
    return account


async def list_organizations(
    db: AsyncSession, *, status_filter: str = 'pending', limit: int = 200
) -> list[tuple[EmployerOrganization, EmployerAccount]]:
    rows = (
        await db.execute(
            select(EmployerOrganization, EmployerAccount)
            .join(EmployerAccount, EmployerAccount.organization_id == EmployerOrganization.id)
            .where(EmployerOrganization.status == status_filter)
            .order_by(EmployerOrganization.created_at.asc())
            .limit(limit)
        )
    ).all()
    return list(rows)


async def approve_organization(
    db: AsyncSession, *, actor: User, org_id: UUID
) -> tuple[EmployerOrganization, EmployerAccount]:
    org = await get_organization_or_404(db, org_id)
    if org.status != 'pending':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only a pending organization can be approved')
    account = await get_account_for_org(db, org.id)

    # Auth-side invite FIRST — if this fails, the org stays pending rather than being marked
    # approved with no matching Supabase identity for its contact.
    redirect_to = f'{settings.employer_portal_url}/accept-invite' if settings.employer_portal_url else None
    try:
        auth_user_id = invite_auth_user(account.email, redirect_to=redirect_to, context='employer')
    except AuthUserAlreadyRegistered:
        # The contact already has an LC Connect account (e.g. they're also a student). Link that
        # identity so approval still succeeds — they sign in with their existing password. A
        # legitimate business decision must not be blocked by an email-reuse edge case.
        auth_user_id = get_auth_user_id_by_email(account.email)
    if auth_user_id is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Could not send the invite because the email service is unavailable. Please try again shortly.',
        )
    account.auth_user_id = auth_user_id

    before = _org_snapshot(org)
    org.status = 'approved'
    org.reviewed_by_id = actor.id
    org.reviewed_at = datetime.now(UTC)
    org.review_note = None

    await record_audit(
        db,
        actor_id=actor.id,
        action='employer_organization.approve',
        target_type='employer_organization',
        target_id=org.id,
        before_data=before,
        after_data=_org_snapshot(org),
    )
    await db.commit()
    await db.refresh(org)
    await db.refresh(account)
    return org, account


async def resend_organization_invite(db: AsyncSession, *, actor: User, org_id: UUID) -> EmployerOrganization:
    """For an already-approved org whose contact never actually completed the invite (email lost,
    landed in spam, code expired). Calling Supabase's invite-by-email again is safe: Supabase
    itself resends for an unconfirmed identity and only errors if the person already finished
    signing up — in which case they need 'forgot password', not another invite, and that's
    exactly the message this surfaces."""
    org = await get_organization_or_404(db, org_id)
    if org.status != 'approved':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail='Only an approved organization can have its invite resent'
        )
    account = await get_account_for_org(db, org.id)

    redirect_to = f'{settings.employer_portal_url}/accept-invite' if settings.employer_portal_url else None
    try:
        auth_user_id = invite_auth_user(account.email, redirect_to=redirect_to, context='employer')
    except AuthUserAlreadyRegistered as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='This contact has already completed sign-up, so a new invite cannot be sent. '
            "Ask them to use 'Forgot your password?' on the employer portal sign-in page instead.",
        ) from exc
    if auth_user_id is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Could not resend the invite because the email service is unavailable. Please try again shortly.',
        )

    await record_audit(
        db,
        actor_id=actor.id,
        action='employer_organization.resend_invite',
        target_type='employer_organization',
        target_id=org.id,
    )
    await db.commit()
    await db.refresh(org)
    return org


async def reject_organization(
    db: AsyncSession, *, actor: User, org_id: UUID, reason: str | None
) -> EmployerOrganization:
    org = await get_organization_or_404(db, org_id)
    if org.status != 'pending':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only a pending organization can be rejected')

    before = _org_snapshot(org)
    org.status = 'rejected'
    org.review_note = reason.strip() if reason else None
    org.reviewed_by_id = actor.id
    org.reviewed_at = datetime.now(UTC)

    await record_audit(
        db,
        actor_id=actor.id,
        action='employer_organization.reject',
        target_type='employer_organization',
        target_id=org.id,
        before_data=before,
        after_data=_org_snapshot(org),
    )
    await db.commit()
    await db.refresh(org)
    return org


# ── opportunity submission review ──────────────────────────────────────────────


def _submission_snapshot(submission: EmployerOpportunitySubmission) -> dict[str, str | None]:
    return {'status': submission.status, 'review_note': submission.review_note}


async def get_submission_or_404(db: AsyncSession, submission_id: UUID) -> EmployerOpportunitySubmission:
    submission = await db.get(EmployerOpportunitySubmission, submission_id)
    if submission is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Opportunity submission not found')
    return submission


async def list_submissions(
    db: AsyncSession, *, status_filter: str = 'pending', limit: int = 200
) -> list[tuple[EmployerOpportunitySubmission, EmployerOrganization]]:
    rows = (
        await db.execute(
            select(EmployerOpportunitySubmission, EmployerOrganization)
            .join(EmployerOrganization, EmployerOrganization.id == EmployerOpportunitySubmission.organization_id)
            .where(EmployerOpportunitySubmission.status == status_filter)
            .order_by(EmployerOpportunitySubmission.created_at.asc())
            .limit(limit)
        )
    ).all()
    return list(rows)


async def approve_submission(
    db: AsyncSession, *, actor: User, submission_id: UUID
) -> EmployerOpportunitySubmission:
    """Publishes through the *existing* campus_hub path — no parallel content table. Idempotent
    against a partial prior failure: `create_post`/`publish_post` each commit on their own, so if
    this function died after publishing but before marking the submission `approved`, a retry
    must not publish a second, duplicate post. `published_post_id` is the guard: once set, a retry
    skips straight to (re-)marking the submission approved instead of creating anything new."""
    submission = await get_submission_or_404(db, submission_id)
    if submission.status != 'pending':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail='Only a pending submission can be approved'
        )

    await publish_submission(db, submission=submission, actor=actor)

    before = _submission_snapshot(submission)
    submission.status = 'approved'
    submission.reviewed_by_id = actor.id
    submission.reviewed_at = datetime.now(UTC)
    submission.review_note = None

    await record_audit(
        db,
        actor_id=actor.id,
        action='employer_opportunity_submission.approve',
        target_type='employer_opportunity_submission',
        target_id=submission.id,
        before_data=before,
        after_data=_submission_snapshot(submission),
    )
    await db.commit()
    await db.refresh(submission)
    return submission


async def reject_submission(
    db: AsyncSession, *, actor: User, submission_id: UUID, reason: str
) -> EmployerOpportunitySubmission:
    submission = await get_submission_or_404(db, submission_id)
    if submission.status != 'pending':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail='Only a pending submission can be rejected'
        )
    stripped_reason = reason.strip()
    if not stripped_reason:
        # Enforced here too, not just the request schema's min_length — a reason recorded, not
        # just a boolean flip, is the whole point of this endpoint.
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='A rejection reason is required')

    before = _submission_snapshot(submission)
    submission.status = 'rejected'
    submission.review_note = stripped_reason
    submission.reviewed_by_id = actor.id
    submission.reviewed_at = datetime.now(UTC)

    await record_audit(
        db,
        actor_id=actor.id,
        action='employer_opportunity_submission.reject',
        target_type='employer_opportunity_submission',
        target_id=submission.id,
        before_data=before,
        after_data=_submission_snapshot(submission),
    )
    await db.commit()
    await db.refresh(submission)
    return submission
