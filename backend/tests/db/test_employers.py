"""Employer self-registration — Blueprint Bond Phase 4 (public, unauthenticated)."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.employers import service
from app.models import EmployerAccount, EmployerOrganization


async def test_register_creates_pending_org_and_account(db):
    org = await service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie Rivera', contact_email='Jamie@Acme.com'
    )
    assert org.status == 'pending'
    assert org.name == 'Acme Corp'

    account = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()
    assert account.email == 'jamie@acme.com'  # normalized
    assert account.display_name == 'Jamie Rivera'
    assert account.auth_user_id is None  # zero access — no Supabase identity yet


async def test_register_duplicate_pending_email_is_409(db):
    await service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email='jamie@acme.com'
    )
    with pytest.raises(HTTPException) as exc:
        await service.register_employer(
            db, organization_name='Acme Corp Again', contact_name='Jamie', contact_email='jamie@acme.com'
        )
    assert exc.value.status_code == 409


async def test_register_after_rejection_stays_blocked_not_reset_to_pending(db):
    org = await service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email='jamie@acme.com'
    )
    org.status = 'rejected'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await service.register_employer(
            db, organization_name='Acme Corp', contact_name='Jamie', contact_email='jamie@acme.com'
        )
    assert exc.value.status_code == 409

    # Confirm the org really did NOT get reset to pending by the second attempt.
    await db.refresh(org)
    assert org.status == 'rejected'


async def test_register_after_approval_is_409(db):
    org = await service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email='jamie@acme.com'
    )
    org.status = 'approved'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await service.register_employer(
            db, organization_name='Acme Corp', contact_name='Jamie', contact_email='jamie@acme.com'
        )
    assert exc.value.status_code == 409


async def test_register_different_emails_creates_separate_orgs(db):
    await service.register_employer(db, organization_name='Acme', contact_name='A', contact_email='a@acme.com')
    await service.register_employer(db, organization_name='Beta', contact_name='B', contact_email='b@beta.com')

    count = (await db.execute(select(func.count()).select_from(EmployerOrganization))).scalar_one()
    assert count == 2
