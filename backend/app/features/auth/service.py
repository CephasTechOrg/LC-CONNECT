"""Auth domain rules: campus email policy and idempotent Supabase bootstrap."""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.features.campus_positions.service import refresh_profile_completed
from app.models import Profile, User
from app.security import SupabaseClaims
from app.shared.email_roles import infer_role_from_email, normalize_campus_email, sync_user_role_from_email


def assert_allowed_email(email: str) -> str:
    try:
        return normalize_campus_email(email)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


def _active_or_raise(user: User) -> User:
    if not user.is_active or user.status != 'active':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Account is inactive or suspended',
        )
    return user


async def get_user_by_auth_id(db: AsyncSession, auth_user_id: UUID) -> User | None:
    result = await db.execute(
        select(User)
        .options(selectinload(User.profile))
        .where(User.auth_user_id == auth_user_id)
    )
    return result.scalar_one_or_none()


async def _reload_user(db: AsyncSession, user_id: UUID) -> User:
    result = await db.execute(
        select(User).options(selectinload(User.profile)).where(User.id == user_id)
    )
    user = result.scalar_one()
    return _active_or_raise(user)


async def bootstrap_user(db: AsyncSession, claims: SupabaseClaims) -> User:
    """Map or create the LC Connect user for a verified Supabase identity.

    Idempotent and concurrency-safe: unique auth_user_id / email constraints
    win races; losers re-load the winning row.
    """
    email = assert_allowed_email(claims.email)

    user = await get_user_by_auth_id(db, claims.sub)
    if user is not None:
        return await _sync_and_return(db, user, claims, email)

    by_email = await db.execute(
        select(User).options(selectinload(User.profile)).where(User.email == email)
    )
    user = by_email.scalar_one_or_none()
    if user is not None:
        if user.auth_user_id is not None and user.auth_user_id != claims.sub:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='Email is linked to a different auth identity',
            )
        user.auth_user_id = claims.sub
        return await _sync_and_return(db, user, claims, email)

    user = User(
        auth_user_id=claims.sub,
        email=email,
        is_verified=claims.email_verified,
        role=infer_role_from_email(email),
        status='active',
        is_active=True,
    )
    db.add(user)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        existing = await get_user_by_auth_id(db, claims.sub)
        if existing is None:
            existing = (
                await db.execute(
                    select(User).options(selectinload(User.profile)).where(User.email == email)
                )
            ).scalar_one_or_none()
        if existing is None:
            raise
        return await _sync_and_return(db, existing, claims, email)

    return await _sync_and_return(db, user, claims, email)


async def _sync_and_return(
    db: AsyncSession,
    user: User,
    claims: SupabaseClaims,
    email: str,
) -> User:
    _active_or_raise(user)
    sync_user_role_from_email(user, email)
    if claims.email_verified and not user.is_verified:
        user.is_verified = True

    # Session has autoflush=False — flush first so pending rows are visible to SELECT.
    await db.flush()
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user.id))
    ).scalar_one_or_none()
    if profile is None:
        db.add(Profile(user_id=user.id, display_name=user.email.split('@', 1)[0]))
        await db.flush()
        profile = (
            await db.execute(select(Profile).where(Profile.user_id == user.id))
        ).scalar_one()

    await refresh_profile_completed(db, user, profile)

    await db.commit()
    return await _reload_user(db, user.id)
