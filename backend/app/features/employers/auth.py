"""Employer authentication — deliberately separate from `app/dependencies.py`'s student/staff
auth path. `EmployerAccount` is never a `User` row (see docs/LC_CONNECT_BLUEPRINT_BOND_INTEGRATION_SPEC.md
§11.0), so it needs its own JWT → identity resolution, even though it verifies the same Supabase
token.
"""

from __future__ import annotations

from dataclasses import dataclass

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import EmployerAccount, EmployerOrganization
from app.security import verify_supabase_access_token
from app.shared.policy_versions import CURRENT_EMPLOYER_AGREEMENT_VERSION

_bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True, slots=True)
class EmployerAuthContext:
    account: EmployerAccount
    organization: EmployerOrganization


async def get_employer_auth_context(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> EmployerAuthContext:
    if credentials is None or credentials.scheme.lower() != 'bearer':
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token')
    try:
        claims = await verify_supabase_access_token(credentials.credentials)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid or expired token') from None

    account = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.auth_user_id == claims.sub))
    ).scalar_one_or_none()
    if account is None or not account.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Employer account not found')

    org = await db.get(EmployerOrganization, account.organization_id)
    if org is None or org.status != 'approved':
        detail = 'Your organization is pending approval' if org and org.status == 'pending' else (
            'Your organization was not approved'
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=detail)

    return EmployerAuthContext(account=account, organization=org)


async def require_approved_employer(
    ctx: EmployerAuthContext = Depends(get_employer_auth_context),
) -> EmployerAuthContext:
    return ctx


async def require_agreed_employer(
    ctx: EmployerAuthContext = Depends(require_approved_employer),
) -> EmployerAuthContext:
    """Approved **and** currently accepting the Employer Agreement.

    Guards scholar data and opportunity submission, so the agreement is enforced by the API rather
    than only by the portal screen. Without this a caller holding a valid token could skip the
    gate component entirely and still read résumés — the same reason the mobile bootstrap check
    exists alongside the signup checkbox.

    Deliberately NOT applied to `/employers/me` (the portal has to be able to ask whether it needs
    to show the gate) or to the accept endpoint itself.
    """
    if ctx.account.agreement_accepted_version < CURRENT_EMPLOYER_AGREEMENT_VERSION:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Please accept the Employer Agreement before viewing scholar information.',
        )
    return ctx
