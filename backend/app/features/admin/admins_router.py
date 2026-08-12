"""Admin-roster endpoints (`/admin/admins/...`).

Split out of `admin/router.py` purely for size — that file crossed the 600-line hard cap. The
membership endpoints are the most self-contained group in it: they all talk to one service
module (`admin/admins.py`) and share one serializer, so they lift out cleanly. Mounted back onto
the same `/admin` prefix, so the API surface is unchanged.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin_aal2
from app.features.admin import admins as admins_admin
from app.features.admin.schema import AdminMembershipRead, InviteAdminRequest, MyAdminScopesRead
from app.models import Profile, User
from app.shared.profiles import get_profile_by_user_id
from app.shared.rate_limit import invite_resend_limit

router = APIRouter()


def _admin_membership_read(membership, user: User, profile: Profile) -> AdminMembershipRead:
    return AdminMembershipRead(
        id=membership.id,
        user_id=membership.user_id,
        role=membership.role,
        status=membership.status,
        invited_at=membership.invited_at,
        revoked_at=membership.revoked_at,
        user_email=user.email,
        display_name=profile.display_name,
    )


@router.get('/admins/me/scopes', response_model=MyAdminScopesRead)
async def get_my_admin_scopes(
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> MyAdminScopesRead:
    """Lets the admin portal gate its own nav — any admin can see their own scopes."""
    scopes = await admins_admin.get_admin_scopes(db, actor.id)
    return MyAdminScopesRead(scopes=sorted(scopes))


@router.get('/admins', response_model=list[AdminMembershipRead])
async def list_admin_memberships(
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[AdminMembershipRead]:
    """The admin roster — read-only, open to any admin (no scope beyond `require_admin_aal2`)."""
    rows = await admins_admin.list_memberships(db)
    return [_admin_membership_read(membership, user, profile) for membership, user, profile in rows]


@router.post('/admins/invite', response_model=AdminMembershipRead, status_code=201)
async def invite_admin(
    payload: InviteAdminRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> AdminMembershipRead:
    """Only Super Admin / School Admin can actually succeed here — `invite_admin` enforces the
    invite matrix itself (403 for anyone else), `require_admin_aal2` is just the base gate."""
    membership, user, profile = await admins_admin.invite_admin(
        db, actor=actor, email=payload.email, role=payload.role
    )

    from app.features.realtime.runtime import emit_notification

    # Belt-and-braces alongside the access-granted email `invite_admin` sends for an existing
    # account: a brand-new invitee has no session or device tokens yet, so this is a harmless
    # no-op for them until they eventually sign in.
    await emit_notification(user_id=user.id, notif_type='admin_membership_invited')
    return _admin_membership_read(membership, user, profile)


@router.post('/admins/me/resign', response_model=list[AdminMembershipRead])
async def resign_admin(
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[AdminMembershipRead]:
    """Step down from your own admin roles. Super Admins are excluded — see
    `admins.resign_admin_membership`. Declared before `/admins/{membership_id}/...` so the
    literal `me` segment is never captured as a membership id."""
    memberships = await admins_admin.resign_admin_membership(db, actor=actor)
    profile = await get_profile_by_user_id(db, actor.id)
    return [_admin_membership_read(membership, actor, profile) for membership in memberships]


@router.post('/admins/{membership_id}/revoke', response_model=AdminMembershipRead)
async def revoke_admin(
    membership_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> AdminMembershipRead:
    membership = await admins_admin.revoke_admin_membership(db, actor=actor, membership_id=membership_id)
    user = await db.get(User, membership.user_id)
    profile = await get_profile_by_user_id(db, membership.user_id)
    return _admin_membership_read(membership, user, profile)


@router.post(
    '/admins/{membership_id}/resend-invite',
    response_model=AdminMembershipRead,
    dependencies=[Depends(invite_resend_limit)],
)
async def resend_admin_invite(
    membership_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> AdminMembershipRead:
    membership = await admins_admin.resend_admin_invite(db, actor=actor, membership_id=membership_id)
    user = await db.get(User, membership.user_id)
    profile = await get_profile_by_user_id(db, membership.user_id)
    return _admin_membership_read(membership, user, profile)
