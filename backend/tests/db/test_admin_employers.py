"""Honors Admin approval queue for employer organizations — Blueprint Bond Phase 4."""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.admin import employers as employers_admin
from app.features.employers import service as register_service
from app.models import AdminAuditLog, AdminMembership


@pytest.fixture(autouse=True)
def _mock_invite(monkeypatch):
    """Never hit real Supabase during tests — a miss here would send a real invite email."""
    monkeypatch.setattr(employers_admin, 'invite_auth_user', lambda email: str(uuid4()))


async def _honors_admin(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    await db.flush()
    db.add(AdminMembership(user_id=admin.id, role='honors_admin'))
    await db.commit()
    return admin


async def _pending_org(db, *, email: str = 'jamie@acme.com'):
    return await register_service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie Rivera', contact_email=email
    )


async def test_approve_sets_status_and_invites_contact(db, factory):
    admin = await _honors_admin(db, factory)
    org = await _pending_org(db)

    approved_org, account = await employers_admin.approve_organization(db, actor=admin, org_id=org.id)
    assert approved_org.status == 'approved'
    assert approved_org.reviewed_by_id == admin.id
    assert approved_org.reviewed_at is not None
    assert account.auth_user_id is not None


async def test_approve_writes_audit_entry(db, factory):
    admin = await _honors_admin(db, factory)
    org = await _pending_org(db)

    approved_org, _ = await employers_admin.approve_organization(db, actor=admin, org_id=org.id)
    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(
                AdminAuditLog.action == 'employer_organization.approve',
                AdminAuditLog.target_id == approved_org.id,
            )
        )
    ).scalar_one()
    assert audit_count == 1


async def test_approve_non_pending_is_409(db, factory):
    admin = await _honors_admin(db, factory)
    org = await _pending_org(db)
    await employers_admin.approve_organization(db, actor=admin, org_id=org.id)

    with pytest.raises(HTTPException) as exc:
        await employers_admin.approve_organization(db, actor=admin, org_id=org.id)
    assert exc.value.status_code == 409


async def test_approve_failure_leaves_org_pending(db, factory, monkeypatch):
    admin = await _honors_admin(db, factory)
    org = await _pending_org(db)
    monkeypatch.setattr(employers_admin, 'invite_auth_user', lambda email: None)

    with pytest.raises(HTTPException) as exc:
        await employers_admin.approve_organization(db, actor=admin, org_id=org.id)
    assert exc.value.status_code == 503

    await db.refresh(org)
    assert org.status == 'pending'  # never flipped to approved without a real invite


async def test_reject_sets_status_and_note(db, factory):
    admin = await _honors_admin(db, factory)
    org = await _pending_org(db)

    rejected = await employers_admin.reject_organization(
        db, actor=admin, org_id=org.id, reason='Not a verified employer partner'
    )
    assert rejected.status == 'rejected'
    assert rejected.review_note == 'Not a verified employer partner'
    assert rejected.reviewed_by_id == admin.id


async def test_reject_writes_audit_entry(db, factory):
    admin = await _honors_admin(db, factory)
    org = await _pending_org(db)
    rejected = await employers_admin.reject_organization(db, actor=admin, org_id=org.id, reason=None)

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(
                AdminAuditLog.action == 'employer_organization.reject',
                AdminAuditLog.target_id == rejected.id,
            )
        )
    ).scalar_one()
    assert audit_count == 1


async def test_reject_non_pending_is_409(db, factory):
    admin = await _honors_admin(db, factory)
    org = await _pending_org(db)
    await employers_admin.reject_organization(db, actor=admin, org_id=org.id, reason=None)

    with pytest.raises(HTTPException) as exc:
        await employers_admin.reject_organization(db, actor=admin, org_id=org.id, reason=None)
    assert exc.value.status_code == 409


async def test_organization_not_found_404(db, factory):
    admin = await _honors_admin(db, factory)
    with pytest.raises(HTTPException) as exc:
        await employers_admin.approve_organization(db, actor=admin, org_id=uuid4())
    assert exc.value.status_code == 404


async def test_list_organizations_filters_by_status(db, factory):
    admin = await _honors_admin(db, factory)
    pending_org = await _pending_org(db, email='pending@acme.com')
    approved_org = await _pending_org(db, email='approved@acme.com')
    await employers_admin.approve_organization(db, actor=admin, org_id=approved_org.id)

    pending_rows = await employers_admin.list_organizations(db, status_filter='pending')
    assert [org.id for org, _ in pending_rows] == [pending_org.id]

    approved_rows = await employers_admin.list_organizations(db, status_filter='approved')
    assert [org.id for org, _ in approved_rows] == [approved_org.id]
