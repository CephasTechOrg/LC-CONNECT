"""Scoped admin permission system (Blueprint Bond Phase 3).

`User.role == 'admin'` (enforced by `require_admin_aal2`) stays the base gate — this module layers
*which* admin scopes an account actually holds, and who may invite/revoke whom. Admin accounts are
never created by a password an admin picks for someone else: `invite_admin` always goes through
Supabase's real invite-by-email (see `app/shared/supabase_admin.invite_auth_user`).
"""

from __future__ import annotations

from collections.abc import Callable, Coroutine
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_admin_aal2
from app.models import AdminMembership, Profile, User
from app.shared.audit import record_audit
from app.shared.email_roles import normalize_campus_email
from app.shared.supabase_admin import (
    AuthUserAlreadyRegistered,
    get_auth_user_id_by_email,
    invite_auth_user,
)

ADMIN_ROLES: tuple[str, ...] = ('super_admin', 'school_admin', 'honors_admin', 'content_admin', 'auditor')

# Deliberately narrow and explicit — a School Admin can grow the operational team but can never
# create a peer or superior (another School Admin or a Super Admin). Everyone below School Admin
# invites nobody.
_INVITE_MATRIX: dict[str, frozenset[str]] = {
    'super_admin': frozenset(ADMIN_ROLES),
    'school_admin': frozenset({'honors_admin', 'content_admin', 'auditor'}),
}


def can_invite(inviter_role: str | None, target_role: str) -> bool:
    """The one place this rule lives — exercised directly by tests, not re-derived ad hoc."""
    if inviter_role is None:
        return False
    return target_role in _INVITE_MATRIX.get(inviter_role, frozenset())


def _primary_role(scopes: set[str]) -> str | None:
    """The single most-permissive scope used for invite/revoke-matrix checks. A person is assumed
    to act with at most one 'rank' for this purpose even if they hold more than one scope."""
    if 'super_admin' in scopes:
        return 'super_admin'
    if 'school_admin' in scopes:
        return 'school_admin'
    return None


async def get_admin_scopes(db: AsyncSession, user_id: UUID) -> set[str]:
    rows = await db.execute(
        select(AdminMembership.role).where(AdminMembership.user_id == user_id, AdminMembership.status == 'active')
    )
    return {role for (role,) in rows.all()}


def require_admin_scope(*allowed_roles: str) -> Callable[..., Coroutine[Any, Any, User]]:
    """A FastAPI dependency factory: `Depends(require_admin_scope('honors_admin'))` — layers a
    scope check on top of `require_admin_aal2` (still the base admin+MFA gate)."""

    async def _dependency(
        actor: User = Depends(require_admin_aal2), db: AsyncSession = Depends(get_db)
    ) -> User:
        scopes = await get_admin_scopes(db, actor.id)
        if not scopes.intersection(allowed_roles):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Requires one of these admin scopes: {', '.join(allowed_roles)}",
            )
        return actor

    return _dependency


async def list_memberships(db: AsyncSession) -> list[tuple[AdminMembership, User, Profile]]:
    rows = (
        await db.execute(
            select(AdminMembership, User, Profile)
            .join(User, User.id == AdminMembership.user_id)
            .join(Profile, Profile.user_id == User.id)
            .where(AdminMembership.status == 'active')
            .order_by(AdminMembership.invited_at.asc())
        )
    ).all()
    return list(rows)


async def invite_admin(
    db: AsyncSession, *, actor: User, email: str, role: str
) -> tuple[AdminMembership, User, Profile]:
    if role not in ADMIN_ROLES:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Unknown admin role')

    actor_scopes = await get_admin_scopes(db, actor.id)
    if not can_invite(_primary_role(actor_scopes), role):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='You are not allowed to invite this role')

    try:
        normalized = normalize_campus_email(email)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)) from exc
    target = (await db.execute(select(User).where(User.email == normalized))).scalar_one_or_none()
    existing = None
    if target is not None:
        existing = (
            await db.execute(
                select(AdminMembership).where(AdminMembership.user_id == target.id, AdminMembership.role == role)
            )
        ).scalar_one_or_none()
        if existing is not None and existing.status == 'active':
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='This person already holds that role')

    # An existing user who already has a real Supabase identity (any prior student/staff account)
    # must NOT be sent a fresh invite — Supabase's invite call is for *new* auth users only and
    # errors on an email that's already registered, which would make it impossible to ever promote
    # an existing account to admin. Only invite when there's genuinely no auth identity yet.
    if target is not None and target.auth_user_id is not None:
        auth_user_id = target.auth_user_id
    else:
        # Auth-side invite FIRST — if this fails, nothing local has been created or changed yet, so
        # there's never a half-created admin row with no matching Supabase invite.
        redirect_to = f'{settings.admin_portal_url}/accept-invite' if settings.admin_portal_url else None
        try:
            auth_user_id = invite_auth_user(normalized, redirect_to=redirect_to)
        except AuthUserAlreadyRegistered:
            # They already have an LC Connect account (e.g. signed up in the mobile app but never
            # bootstrapped a local row). Link that identity and grant the role — they sign in with
            # their existing password, and the in-app notification tells them. Blocking here would
            # make a legitimate promotion impossible.
            auth_user_id = get_auth_user_id_by_email(normalized)
        if auth_user_id is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail='Could not send the invite because the email service is unavailable. Please try again shortly.',
            )

    if target is None:
        target = User(email=normalized, role='admin', auth_user_id=auth_user_id, is_verified=True)
        db.add(target)
        await db.flush()
        db.add(Profile(user_id=target.id, display_name=normalized.split('@')[0]))
        await db.flush()
    else:
        target.role = 'admin'
        if target.auth_user_id is None:
            target.auth_user_id = auth_user_id

    now = datetime.now(UTC)
    if existing is not None:
        existing.status = 'active'
        existing.invited_by_id = actor.id
        existing.invited_at = now
        existing.revoked_at = None
        membership = existing
    else:
        membership = AdminMembership(user_id=target.id, role=role, invited_by_id=actor.id)
        db.add(membership)
        await db.flush()

    await record_audit(
        db,
        actor_id=actor.id,
        action='admin_membership.invite',
        target_type='admin_membership',
        target_id=membership.id,
        after_data={'role': role, 'email': normalized},
    )
    await db.commit()
    await db.refresh(membership)

    profile = (await db.execute(select(Profile).where(Profile.user_id == target.id))).scalar_one()
    return membership, target, profile


async def revoke_admin_membership(db: AsyncSession, *, actor: User, membership_id: UUID) -> AdminMembership:
    membership = await db.get(AdminMembership, membership_id)
    if membership is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Admin membership not found')
    if membership.status != 'active':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='This membership is not active')

    actor_scopes = await get_admin_scopes(db, actor.id)
    if not can_invite(_primary_role(actor_scopes), membership.role):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='You are not allowed to revoke this role')

    before = {'status': membership.status}
    membership.status = 'revoked'
    membership.revoked_at = datetime.now(UTC)

    await record_audit(
        db,
        actor_id=actor.id,
        action='admin_membership.revoke',
        target_type='admin_membership',
        target_id=membership.id,
        before_data=before,
        after_data={'status': 'revoked'},
    )
    await db.commit()
    await db.refresh(membership)
    return membership


async def resend_admin_invite(db: AsyncSession, *, actor: User, membership_id: UUID) -> AdminMembership:
    """For an active membership whose invitee never actually completed sign-up (email lost,
    landed in spam, code expired). Calling Supabase's invite-by-email again is safe: Supabase
    itself resends for an unconfirmed identity and only errors if the person already finished
    signing up — in which case they need 'forgot password', not another invite."""
    membership = await db.get(AdminMembership, membership_id)
    if membership is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Admin membership not found')
    if membership.status != 'active':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='This membership is not active')

    actor_scopes = await get_admin_scopes(db, actor.id)
    if not can_invite(_primary_role(actor_scopes), membership.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail='You are not allowed to resend an invite for this role'
        )

    target = await db.get(User, membership.user_id)
    redirect_to = f'{settings.admin_portal_url}/accept-invite' if settings.admin_portal_url else None
    try:
        auth_user_id = invite_auth_user(target.email, redirect_to=redirect_to)
    except AuthUserAlreadyRegistered as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='This person has already completed sign-up, so a new invite cannot be sent. '
            "Ask them to use 'Forgot your password?' on the sign-in page instead.",
        ) from exc
    if auth_user_id is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Could not resend the invite because the email service is unavailable. Please try again shortly.',
        )

    await record_audit(
        db,
        actor_id=actor.id,
        action='admin_membership.resend_invite',
        target_type='admin_membership',
        target_id=membership.id,
    )
    await db.commit()
    await db.refresh(membership)
    return membership
