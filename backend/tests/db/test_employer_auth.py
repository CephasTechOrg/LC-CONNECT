"""Employer auth context — pending/rejected/unknown employer resolution."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.employers import auth as employers_auth
from app.features.employers import service
from app.features.employers.router import get_my_employer_context
from app.models import EmployerAccount


def _creds() -> SimpleNamespace:
    return SimpleNamespace(scheme='Bearer', credentials='fake-token')


async def _account_for(db, org):
    return (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()


async def test_pending_org_gets_403_pending_message(db, monkeypatch):
    org = await service.register_employer(
        db, organization_name='Acme', contact_name='Jamie', contact_email='jamie@acme.com'
    )
    account = await _account_for(db, org)
    account.auth_user_id = uuid4()
    await db.commit()

    monkeypatch.setattr(
        employers_auth, 'verify_supabase_access_token', AsyncMock(return_value=SimpleNamespace(sub=account.auth_user_id))
    )
    with pytest.raises(HTTPException) as exc:
        await employers_auth.get_employer_auth_context(credentials=_creds(), db=db)
    assert exc.value.status_code == 403
    assert 'pending' in exc.value.detail.lower()


async def test_rejected_org_gets_403_not_approved_message(db, monkeypatch):
    org = await service.register_employer(
        db, organization_name='Acme', contact_name='Jamie', contact_email='jamie2@acme.com'
    )
    account = await _account_for(db, org)
    account.auth_user_id = uuid4()
    org.status = 'rejected'
    await db.commit()

    monkeypatch.setattr(
        employers_auth, 'verify_supabase_access_token', AsyncMock(return_value=SimpleNamespace(sub=account.auth_user_id))
    )
    with pytest.raises(HTTPException) as exc:
        await employers_auth.get_employer_auth_context(credentials=_creds(), db=db)
    assert exc.value.status_code == 403
    assert 'not approved' in exc.value.detail.lower()


async def test_approved_org_resolves_context(db, monkeypatch):
    org = await service.register_employer(
        db, organization_name='Acme', contact_name='Jamie', contact_email='jamie3@acme.com'
    )
    account = await _account_for(db, org)
    account.auth_user_id = uuid4()
    org.status = 'approved'
    await db.commit()

    monkeypatch.setattr(
        employers_auth, 'verify_supabase_access_token', AsyncMock(return_value=SimpleNamespace(sub=account.auth_user_id))
    )
    ctx = await employers_auth.get_employer_auth_context(credentials=_creds(), db=db)
    assert ctx.account.id == account.id
    assert ctx.organization.id == org.id


async def test_unknown_auth_user_id_is_401(db, monkeypatch):
    monkeypatch.setattr(
        employers_auth, 'verify_supabase_access_token', AsyncMock(return_value=SimpleNamespace(sub=uuid4()))
    )
    with pytest.raises(HTTPException) as exc:
        await employers_auth.get_employer_auth_context(credentials=_creds(), db=db)
    assert exc.value.status_code == 401


async def test_missing_bearer_token_is_401(db):
    with pytest.raises(HTTPException) as exc:
        await employers_auth.get_employer_auth_context(credentials=None, db=db)
    assert exc.value.status_code == 401


async def test_get_my_employer_context_shape(db, monkeypatch):
    org = await service.register_employer(
        db, organization_name='Acme', contact_name='Jamie', contact_email='jamie4@acme.com'
    )
    account = await _account_for(db, org)
    account.auth_user_id = uuid4()
    org.status = 'approved'
    await db.commit()

    monkeypatch.setattr(
        employers_auth, 'verify_supabase_access_token', AsyncMock(return_value=SimpleNamespace(sub=account.auth_user_id))
    )
    ctx = await employers_auth.get_employer_auth_context(credentials=_creds(), db=db)
    result = await get_my_employer_context(ctx=ctx)
    assert result.organization_id == org.id
    assert result.organization_name == 'Acme'
    assert result.organization_status == 'approved'
    assert result.email == account.email
