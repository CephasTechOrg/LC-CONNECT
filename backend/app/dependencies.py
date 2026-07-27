from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import settings
from app.database import get_db
from app.models import User
from app.security import SupabaseClaims, decode_access_token, verify_supabase_access_token

bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True, slots=True)
class AuthContext:
    user: User
    claims: SupabaseClaims | None
    legacy: bool


async def get_supabase_claims(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> SupabaseClaims:
    if credentials is None or credentials.scheme.lower() != 'bearer':
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token')
    try:
        return await verify_supabase_access_token(credentials.credentials)
    except ValueError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid or expired token') from None


async def _load_user(db: AsyncSession, *, auth_user_id: UUID | None = None, user_id: UUID | None = None) -> User | None:
    stmt = select(User).options(selectinload(User.profile))
    if auth_user_id is not None:
        stmt = stmt.where(User.auth_user_id == auth_user_id)
    elif user_id is not None:
        stmt = stmt.where(User.id == user_id)
    else:
        return None
    return (await db.execute(stmt)).scalar_one_or_none()


def _ensure_active(user: User | None) -> User:
    if user is None or not user.is_active or user.status != 'active':
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Inactive or suspended user')
    return user


async def get_auth_context(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> AuthContext:
    if credentials is None or credentials.scheme.lower() != 'bearer':
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token')

    token = credentials.credentials

    try:
        claims = await verify_supabase_access_token(token)
    except ValueError:
        claims = None

    if claims is not None:
        user = await _load_user(db, auth_user_id=claims.sub)
        if user is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail='User not bootstrapped. Call POST /auth/bootstrap first.',
            )
        return AuthContext(user=_ensure_active(user), claims=claims, legacy=False)

    if not settings.auth_legacy_enabled:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid or expired token')

    legacy_id = decode_access_token(token)
    if legacy_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid or expired token')

    user = await _load_user(db, user_id=legacy_id)
    return AuthContext(user=_ensure_active(user), claims=None, legacy=True)


async def get_current_user(ctx: AuthContext = Depends(get_auth_context)) -> User:
    return ctx.user


async def require_verified_student(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_verified:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Verified student required')
    return current_user


async def require_verified_connect_student(
    current_user: User = Depends(require_verified_student),
) -> User:
    """Gate social discovery, connections, and match messaging to students only.

    Staff and admins keep email-verified access to Campus Hub, activities, and
    profile — but must not participate in student social matching.
    """
    if current_user.role != 'student':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Social matching is only available to student accounts',
        )
    return current_user


async def require_verified_user(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_verified:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Verified account required')
    return current_user


async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != 'admin':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Admin access required')
    return current_user


async def require_admin_aal2(ctx: AuthContext = Depends(get_auth_context)) -> User:
    if ctx.user.role != 'admin':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Admin access required')
    if ctx.legacy:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Admin actions require Supabase MFA (aal2)',
        )
    if ctx.claims is None or ctx.claims.aal != 'aal2':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Admin actions require MFA (aal2)',
        )
    return ctx.user
