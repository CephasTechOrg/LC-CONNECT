"""An admin must never be able to remove their own access.

Each of these actions was self-inflicted and unrecoverable to different degrees — suspension
worst of all, since the suspended account can no longer authenticate to undo it. Removing an
admin's access is always someone else's job.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.account import service as account_service
from app.features.admin import admins as admins_service
from app.features.admin import service as admin_service
from app.models import AdminMembership, User


@pytest.fixture(autouse=True)
def _mock_invite(monkeypatch):
    monkeypatch.setattr(admins_service, 'invite_auth_user', lambda email, **kwargs: str(uuid4()))


async def _admin_with_scope(db, factory, role: str) -> User:
    admin = await factory.user(display_name=f'{role} Admin')
    admin.role = 'admin'
    await db.flush()
    db.add(AdminMembership(user_id=admin.id, role=role))
    await db.commit()
    return admin


async def _membership_of(db, user: User) -> AdminMembership:
    return (
        await db.execute(select(AdminMembership).where(AdminMembership.user_id == user.id))
    ).scalar_one()


# ── revoking your own membership ────────────────────────────────────────────────────


async def test_super_admin_cannot_revoke_their_own_membership(db, factory):
    """Tested with a second Super Admin present, so this is the self-check and not the
    last-Super-Admin guard doing the work."""
    actor = await _admin_with_scope(db, factory, 'super_admin')
    await _admin_with_scope(db, factory, 'super_admin')  # a second one exists
    mine = await _membership_of(db, actor)

    with pytest.raises(HTTPException) as exc:
        await admins_service.revoke_admin_membership(db, actor=actor, membership_id=mine.id)
    assert exc.value.status_code == 409
    assert 'their own access' in exc.value.detail

    await db.refresh(actor)
    assert actor.role == 'admin'
    assert (await _membership_of(db, actor)).status == 'active'


async def test_another_admin_can_still_revoke_them(db, factory):
    """The self-check must not make revocation impossible — only self-service."""
    actor = await _admin_with_scope(db, factory, 'super_admin')
    other = await _admin_with_scope(db, factory, 'content_admin')

    revoked = await admins_service.revoke_admin_membership(
        db, actor=actor, membership_id=(await _membership_of(db, other)).id
    )
    assert revoked.status == 'revoked'


# ── suspending your own account ─────────────────────────────────────────────────────


async def test_admin_cannot_suspend_themselves(db, factory):
    """The worst lockout available: a suspended account cannot authenticate, and reactivating
    requires authenticating."""
    actor = await _admin_with_scope(db, factory, 'super_admin')

    with pytest.raises(HTTPException) as exc:
        await admin_service.suspend_user(db, actor.id, actor_id=actor.id)
    assert exc.value.status_code == 409

    await db.refresh(actor)
    assert actor.status == 'active' and actor.is_active is True


async def test_admin_can_still_suspend_someone_else(db, factory):
    actor = await _admin_with_scope(db, factory, 'super_admin')
    target = await factory.user(display_name='Rule Breaker')

    suspended = await admin_service.suspend_user(db, target.id, actor_id=actor.id)
    assert suspended.status == 'suspended' and suspended.is_active is False


# ── deleting your own account ───────────────────────────────────────────────────────


async def test_last_super_admin_cannot_delete_their_account(db, factory):
    actor = await _admin_with_scope(db, factory, 'super_admin')

    with pytest.raises(HTTPException) as exc:
        await account_service.delete_account(db, actor)
    assert exc.value.status_code == 409
    assert 'only Super Admin' in exc.value.detail

    await db.refresh(actor)
    assert actor.status == 'active'


async def test_super_admin_can_delete_once_another_exists(db, factory):
    actor = await _admin_with_scope(db, factory, 'super_admin')
    await _admin_with_scope(db, factory, 'super_admin')

    await account_service.delete_account(db, actor)

    await db.refresh(actor)
    assert actor.status == 'deleted' and actor.is_active is False


async def test_non_admin_deletion_is_unaffected(db, factory):
    student = await factory.user(display_name='Ordinary Student')

    await account_service.delete_account(db, student)

    await db.refresh(student)
    assert student.status == 'deleted'


# ── stepping down: allowed for everyone EXCEPT the Super Admin ───────────────────────


async def test_content_admin_can_resign(db, factory):
    """The invite matrix never let a Content Admin reach the revoke path at all, so before this
    they had no way to remove their own access."""
    actor = await _admin_with_scope(db, factory, 'content_admin')

    revoked = await admins_service.resign_admin_membership(db, actor=actor)

    assert [m.status for m in revoked] == ['revoked']
    await db.refresh(actor)
    assert actor.role == 'staff'
    assert await admins_service.get_admin_scopes(db, actor.id) == set()


async def test_resign_drops_every_role_held(db, factory):
    actor = await _admin_with_scope(db, factory, 'content_admin')
    db.add(AdminMembership(user_id=actor.id, role='auditor'))
    await db.commit()

    revoked = await admins_service.resign_admin_membership(db, actor=actor)

    assert {m.role for m in revoked} == {'content_admin', 'auditor'}
    assert await admins_service.get_admin_scopes(db, actor.id) == set()


async def test_super_admin_cannot_resign(db, factory):
    actor = await _admin_with_scope(db, factory, 'super_admin')
    await _admin_with_scope(db, factory, 'super_admin')  # even with a second one present

    with pytest.raises(HTTPException) as exc:
        await admins_service.resign_admin_membership(db, actor=actor)
    assert exc.value.status_code == 409

    await db.refresh(actor)
    assert actor.role == 'admin'


async def test_school_admin_may_revoke_their_own_lesser_scope(db, factory):
    """Self-revoke is blocked only for super_admin — a lesser scope is an ordinary step-down."""
    actor = await _admin_with_scope(db, factory, 'school_admin')
    db.add(AdminMembership(user_id=actor.id, role='honors_admin'))
    await db.commit()
    honors = (
        await db.execute(
            select(AdminMembership).where(
                AdminMembership.user_id == actor.id, AdminMembership.role == 'honors_admin'
            )
        )
    ).scalar_one()

    revoked = await admins_service.revoke_admin_membership(db, actor=actor, membership_id=honors.id)

    assert revoked.status == 'revoked'
    await db.refresh(actor)
    assert actor.role == 'admin'  # still a School Admin


# ── deleted admins must stop counting as active ─────────────────────────────────────


async def test_account_deletion_retires_admin_memberships(db, factory):
    """Otherwise a deleted Super Admin keeps counting, and the true last one could revoke
    themselves believing a second still existed."""
    first = await _admin_with_scope(db, factory, 'super_admin')
    second = await _admin_with_scope(db, factory, 'super_admin')

    await account_service.delete_account(db, second)

    assert await admins_service.get_admin_scopes(db, second.id) == set()

    # `first` is now genuinely the last Super Admin, and must be protected as such.
    mine = (
        await db.execute(
            select(AdminMembership).where(
                AdminMembership.user_id == first.id, AdminMembership.status == 'active'
            )
        )
    ).scalar_one()
    with pytest.raises(HTTPException) as exc:
        await admins_service.revoke_admin_membership(db, actor=first, membership_id=mine.id)
    assert exc.value.status_code == 409
