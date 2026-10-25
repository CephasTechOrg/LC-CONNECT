"""Auth domain rules: campus email policy and idempotent Supabase bootstrap."""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.features.campus_positions.service import refresh_profile_completed
from app.models import Profile, User
from app.security import SupabaseClaims
from app.shared.account_status import ACCOUNT_INACTIVE_DETAIL, ACCOUNT_SUSPENDED_DETAIL
from app.shared.email_roles import (
    infer_role_from_email,
    normalize_campus_email,
    normalize_personal_contact_email,
    sync_user_role_from_email,
)
from app.shared.person_names import names_from_metadata
from app.shared.policy_versions import CURRENT_POLICY_VERSION

_CONTACT_EMAIL_METADATA_KEYS = ('contact_email', 'personal_email')


def assert_allowed_email(email: str) -> str:
    try:
        return normalize_campus_email(email)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


def _raw_contact_email_from_claims(claims: SupabaseClaims) -> str | None:
    for bucket in ('user_metadata', 'app_metadata'):
        metadata = claims.raw.get(bucket) or {}
        if not isinstance(metadata, dict):
            continue
        for key in _CONTACT_EMAIL_METADATA_KEYS:
            value = metadata.get(key)
            if isinstance(value, str) and value.strip():
                return value
    return None


def contact_email_from_claims(claims: SupabaseClaims) -> str | None:
    """Personal inbox from Supabase metadata, validated. None when unset."""
    raw = _raw_contact_email_from_claims(claims)
    if raw is None:
        return None
    try:
        return normalize_personal_contact_email(raw)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc


def _sync_contact_email(user: User, claims: SupabaseClaims) -> None:
    contact = contact_email_from_claims(claims)
    if contact is not None:
        user.contact_email = contact


def names_from_claims(claims: SupabaseClaims) -> tuple[str, str] | None:
    """(first, last) from signup metadata, validated; None when absent or invalid."""
    for bucket in ('user_metadata', 'app_metadata'):
        names = names_from_metadata(claims.raw.get(bucket))
        if names is not None:
            return names
    return None


def _sync_names(user: User, claims: SupabaseClaims) -> None:
    """Fills the names once, from signup — never overwrites ones already stored.

    Metadata is client-writable and replayed on every bootstrap, so letting it win on each sign-in
    would make a stale token silently undo a later correction.
    """
    if user.first_name and user.last_name:
        return
    names = names_from_claims(claims)
    if names is not None:
        user.first_name, user.last_name = names


def _accepted_version_from_claims(claims: SupabaseClaims) -> int:
    """Policy version the client says was accepted at signup, from Supabase user metadata.

    The mobile app cannot record acceptance server-side at signup — there is no session and no user
    row until the email code is confirmed — so it rides along in `signUp(data: {...})` the same way
    `contact_email` does, and lands here on first bootstrap.

    **Clamped to `CURRENT_POLICY_VERSION`.** Metadata is client-writable, so an untrusted value
    claiming version 9999 would otherwise skip every future gate permanently. Clamping means the
    worst a tampered client achieves is claiming today's version — which is a user lying about
    consenting to rules that bind them, and self-defeating.
    """
    for bucket in ('user_metadata', 'app_metadata'):
        metadata = claims.raw.get(bucket) or {}
        if not isinstance(metadata, dict):
            continue
        raw = metadata.get('policies_accepted_version')
        if isinstance(raw, bool) or not isinstance(raw, (int, str)):
            continue
        try:
            claimed = int(raw)
        except (TypeError, ValueError):
            continue
        if claimed > 0:
            return min(claimed, CURRENT_POLICY_VERSION)
    return 0


def _sync_policy_acceptance(user: User, claims: SupabaseClaims) -> None:
    """Only ever moves the stored version forward, never back.

    A stale client that omits the metadata must not un-accept someone who already agreed, and a
    re-login must not reset an acceptance recorded by `POST /auth/accept-policies`.
    """
    claimed = _accepted_version_from_claims(claims)
    if claimed > user.policies_accepted_version:
        user.policies_accepted_version = claimed
        user.policies_accepted_at = datetime.now(UTC)


def _active_or_raise(user: User) -> User:
    if user.status == 'suspended':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=ACCOUNT_SUSPENDED_DETAIL,
        )
    if not user.is_active or user.status != 'active':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=ACCOUNT_INACTIVE_DETAIL,
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
    contact = contact_email_from_claims(claims)

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
        contact_email=contact,
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
    _sync_contact_email(user, claims)
    _sync_names(user, claims)
    _sync_policy_acceptance(user, claims)
    if claims.email_verified and not user.is_verified:
        user.is_verified = True

    # Session has autoflush=False — flush first so pending rows are visible to SELECT.
    await db.flush()
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user.id))
    ).scalar_one_or_none()
    if profile is None:
        # The name given at signup, so the first thing a new student sees is themselves — not the
        # local part of their campus address. Older accounts without one keep the old default.
        display_name = (
            f'{user.first_name} {user.last_name}'
            if user.first_name and user.last_name
            else user.email.split('@', 1)[0]
        )
        db.add(Profile(user_id=user.id, display_name=display_name))
        await db.flush()
        profile = (
            await db.execute(select(Profile).where(Profile.user_id == user.id))
        ).scalar_one()

    await refresh_profile_completed(db, user, profile)

    await db.commit()
    return await _reload_user(db, user.id)
