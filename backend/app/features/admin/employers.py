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

from app.models import EmployerAccount, EmployerOrganization, User
from app.shared.audit import record_audit
from app.shared.supabase_admin import invite_auth_user


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
    auth_user_id = invite_auth_user(account.email)
    if auth_user_id is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Could not send the invite — try again later'
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
