"""Scoped admin permission system — invite matrix, invite/revoke, and scope enforcement."""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.admin import admins as admins_service
from app.models import AdminAuditLog, AdminMembership, User


@pytest.fixture(autouse=True)
def _mock_invite(monkeypatch):
    """Every test in this file that invites someone must never hit real Supabase — a bad mock
    here would mean real invite emails going out during a test run."""
    monkeypatch.setattr(admins_service, 'invite_auth_user', lambda email, **kwargs: str(uuid4()))


async def _admin_with_scope(db, factory, role: str) -> User:
    admin = await factory.user(display_name=f'{role} Admin')
    admin.role = 'admin'
    await db.flush()
    db.add(AdminMembership(user_id=admin.id, role=role))
    await db.commit()
    return admin


# ── can_invite matrix (pure function) ────────────────────────────────────────────


@pytest.mark.parametrize(
    ('inviter_role', 'target_role', 'expected'),
    [
        ('super_admin', 'super_admin', True),
        ('super_admin', 'school_admin', True),
        ('super_admin', 'honors_admin', True),
        ('super_admin', 'content_admin', True),
        ('super_admin', 'auditor', True),
        ('school_admin', 'honors_admin', True),
        ('school_admin', 'content_admin', True),
        ('school_admin', 'auditor', True),
        ('school_admin', 'school_admin', False),
        ('school_admin', 'super_admin', False),
        ('honors_admin', 'auditor', False),
        ('content_admin', 'auditor', False),
        ('auditor', 'auditor', False),
        (None, 'auditor', False),
    ],
)
def test_can_invite_matrix(inviter_role, target_role, expected):
    assert admins_service.can_invite(inviter_role, target_role) is expected


# ── get_admin_scopes ──────────────────────────────────────────────────────────────


async def test_get_admin_scopes_excludes_revoked(db, factory):
    admin = await factory.user(display_name='Multi Admin')
    admin.role = 'admin'
    await db.flush()
    db.add(AdminMembership(user_id=admin.id, role='honors_admin'))
    db.add(AdminMembership(user_id=admin.id, role='content_admin', status='revoked'))
    await db.commit()

    scopes = await admins_service.get_admin_scopes(db, admin.id)
    assert scopes == {'honors_admin'}


# ── invite_admin ──────────────────────────────────────────────────────────────────


async def test_super_admin_can_invite_any_role(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    student = await factory.user(display_name='Future Admin')

    membership, user, profile = await admins_service.invite_admin(
        db, actor=super_admin, email=student.email, role='honors_admin'
    )
    assert membership.role == 'honors_admin'
    assert membership.status == 'active'
    assert user.role == 'admin'
    assert profile.user_id == user.id


async def test_super_admin_can_invite_new_email_creates_user_and_profile(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')

    membership, user, profile = await admins_service.invite_admin(
        db, actor=super_admin, email='brand.new@livingstone.edu', role='content_admin'
    )
    assert user.email == 'brand.new@livingstone.edu'
    assert user.role == 'admin'
    assert user.auth_user_id is not None
    assert profile.display_name  # non-empty default from the email local-part


async def test_invite_existing_auth_identity_is_never_resent_an_invite(db, factory, monkeypatch):
    """Promoting an existing verified student/staff account to admin must NOT call Supabase's
    invite-by-email again — that call is for brand-new auth users only and errors on an email
    that's already registered, which would otherwise make it impossible to ever promote an
    existing account."""
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Already Has Account')
    target.auth_user_id = uuid4()
    await db.commit()

    def _fail_if_called(email, **kwargs):
        raise AssertionError('invite_auth_user must not be called for an already-registered user')

    monkeypatch.setattr(admins_service, 'invite_auth_user', _fail_if_called)

    membership, user, _ = await admins_service.invite_admin(
        db, actor=super_admin, email=target.email, role='content_admin'
    )
    assert membership.role == 'content_admin'
    assert user.auth_user_id == target.auth_user_id


async def test_school_admin_can_invite_honors_content_auditor(db, factory):
    school_admin = await _admin_with_scope(db, factory, 'school_admin')
    for role in ('honors_admin', 'content_admin', 'auditor'):
        target = await factory.user(display_name=f'Target {role}')
        membership, _, _ = await admins_service.invite_admin(db, actor=school_admin, email=target.email, role=role)
        assert membership.role == role


async def test_school_admin_cannot_invite_school_or_super_admin(db, factory):
    school_admin = await _admin_with_scope(db, factory, 'school_admin')
    target = await factory.user(display_name='Target')

    for role in ('school_admin', 'super_admin'):
        with pytest.raises(HTTPException) as exc:
            await admins_service.invite_admin(db, actor=school_admin, email=target.email, role=role)
        assert exc.value.status_code == 403


async def test_honors_admin_cannot_invite_anyone(db, factory):
    honors_admin = await _admin_with_scope(db, factory, 'honors_admin')
    target = await factory.user(display_name='Target')

    with pytest.raises(HTTPException) as exc:
        await admins_service.invite_admin(db, actor=honors_admin, email=target.email, role='auditor')
    assert exc.value.status_code == 403


async def test_invite_unknown_role_is_422(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Target')

    with pytest.raises(HTTPException) as exc:
        await admins_service.invite_admin(db, actor=super_admin, email=target.email, role='not_a_real_role')
    assert exc.value.status_code == 422


async def test_invite_non_campus_email_is_422_not_500(db, factory):
    """`normalize_campus_email` raises a bare `ValueError` — it must be caught and turned into a
    clean 422, not bubble up as an unhandled 500."""
    super_admin = await _admin_with_scope(db, factory, 'super_admin')

    with pytest.raises(HTTPException) as exc:
        await admins_service.invite_admin(db, actor=super_admin, email='someone@gmail.com', role='auditor')
    assert exc.value.status_code == 422


async def test_invite_duplicate_active_role_is_409(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Target')
    await admins_service.invite_admin(db, actor=super_admin, email=target.email, role='content_admin')

    with pytest.raises(HTTPException) as exc:
        await admins_service.invite_admin(db, actor=super_admin, email=target.email, role='content_admin')
    assert exc.value.status_code == 409


async def test_invite_reactivates_after_revoke(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Target')
    first, _, _ = await admins_service.invite_admin(db, actor=super_admin, email=target.email, role='content_admin')
    await admins_service.revoke_admin_membership(db, actor=super_admin, membership_id=first.id)

    reactivated, _, _ = await admins_service.invite_admin(
        db, actor=super_admin, email=target.email, role='content_admin'
    )
    assert reactivated.id == first.id
    assert reactivated.status == 'active'
    assert reactivated.revoked_at is None


async def test_invite_writes_audit_entry(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Target')
    membership, _, _ = await admins_service.invite_admin(db, actor=super_admin, email=target.email, role='auditor')

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(AdminAuditLog.action == 'admin_membership.invite', AdminAuditLog.target_id == membership.id)
        )
    ).scalar_one()
    assert audit_count == 1


async def test_invite_failure_leaves_nothing_half_created(db, factory, monkeypatch):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    monkeypatch.setattr(admins_service, 'invite_auth_user', lambda email, **kwargs: None)

    with pytest.raises(HTTPException) as exc:
        await admins_service.invite_admin(db, actor=super_admin, email='ghost@livingstone.edu', role='auditor')
    assert exc.value.status_code == 503

    orphan = (await db.execute(select(User).where(User.email == 'ghost@livingstone.edu'))).scalar_one_or_none()
    assert orphan is None


# ── revoke_admin_membership ────────────────────────────────────────────────────────


async def test_revoke_sets_revoked_and_writes_audit(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Target')
    membership, _, _ = await admins_service.invite_admin(db, actor=super_admin, email=target.email, role='auditor')

    revoked = await admins_service.revoke_admin_membership(db, actor=super_admin, membership_id=membership.id)
    assert revoked.status == 'revoked'
    assert revoked.revoked_at is not None

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(AdminAuditLog.action == 'admin_membership.revoke', AdminAuditLog.target_id == membership.id)
        )
    ).scalar_one()
    assert audit_count == 1


async def test_school_admin_cannot_revoke_super_admin(db, factory):
    school_admin = await _admin_with_scope(db, factory, 'school_admin')
    other_super_admin = await _admin_with_scope(db, factory, 'super_admin')
    membership = (
        await db.execute(select(AdminMembership).where(AdminMembership.user_id == other_super_admin.id))
    ).scalar_one()

    with pytest.raises(HTTPException) as exc:
        await admins_service.revoke_admin_membership(db, actor=school_admin, membership_id=membership.id)
    assert exc.value.status_code == 403


async def test_revoke_not_found_404(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')

    with pytest.raises(HTTPException) as exc:
        await admins_service.revoke_admin_membership(db, actor=super_admin, membership_id=uuid4())
    assert exc.value.status_code == 404


async def test_revoke_already_revoked_is_409(db, factory):
    super_admin = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Target')
    membership, _, _ = await admins_service.invite_admin(db, actor=super_admin, email=target.email, role='auditor')
    await admins_service.revoke_admin_membership(db, actor=super_admin, membership_id=membership.id)

    with pytest.raises(HTTPException) as exc:
        await admins_service.revoke_admin_membership(db, actor=super_admin, membership_id=membership.id)
    assert exc.value.status_code == 409


# ── require_admin_scope dependency ─────────────────────────────────────────────────


async def test_require_admin_scope_allows_matching_scope(db, factory):
    honors_admin = await _admin_with_scope(db, factory, 'honors_admin')
    dep = admins_service.require_admin_scope('honors_admin')
    result = await dep(actor=honors_admin, db=db)
    assert result.id == honors_admin.id


async def test_require_admin_scope_rejects_missing_scope(db, factory):
    honors_admin = await _admin_with_scope(db, factory, 'honors_admin')
    dep = admins_service.require_admin_scope('super_admin')
    with pytest.raises(HTTPException) as exc:
        await dep(actor=honors_admin, db=db)
    assert exc.value.status_code == 403
