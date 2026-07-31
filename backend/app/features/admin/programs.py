"""Admin verify/revoke workflow for program memberships (Blueprint Bond foundation).

Membership is never self-declared: an Honors admin verifies a student from an official roster by
email, and can revoke it later. Re-verifying after a revoke reactivates the same row rather than
creating a duplicate (unique per user+program).
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Profile, Program, ProgramMembership, User
from app.shared.audit import record_audit
from app.shared.email_roles import normalize_campus_email
from app.shared.profiles import get_profile_by_user_id


def _membership_snapshot(membership: ProgramMembership) -> dict[str, str | None]:
    return {
        'status': membership.status,
        'verified_at': membership.verified_at.isoformat() if membership.verified_at else None,
        'revoked_at': membership.revoked_at.isoformat() if membership.revoked_at else None,
    }


async def get_program_by_slug_or_404(db: AsyncSession, slug: str) -> Program:
    program = (
        await db.execute(select(Program).where(Program.slug == slug, Program.is_active.is_(True)))
    ).scalar_one_or_none()
    if program is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Program not found')
    return program


async def list_memberships(
    db: AsyncSession, *, program_id: UUID, status_filter: str = 'active', limit: int = 200
) -> list[tuple[ProgramMembership, User, Profile]]:
    rows = (
        await db.execute(
            select(ProgramMembership, User, Profile)
            .join(User, User.id == ProgramMembership.user_id)
            .join(Profile, Profile.user_id == User.id)
            .where(ProgramMembership.program_id == program_id, ProgramMembership.status == status_filter)
            .order_by(ProgramMembership.created_at.asc())
            .limit(limit)
        )
    ).all()
    return list(rows)


async def verify_membership(
    db: AsyncSession, *, actor: User, program: Program, email: str
) -> tuple[ProgramMembership, User, Profile]:
    """Grant (or reactivate) membership for the student at `email`. A duplicate verify on an
    already-active membership is a 409 — this is not the reactivation path."""
    normalized = normalize_campus_email(email)
    target = (await db.execute(select(User).where(User.email == normalized))).scalar_one_or_none()
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No account found for that email')
    if target.role != 'student':
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Only students can be enrolled in a program'
        )

    existing = (
        await db.execute(
            select(ProgramMembership).where(
                ProgramMembership.user_id == target.id,
                ProgramMembership.program_id == program.id,
            )
        )
    ).scalar_one_or_none()

    now = datetime.now(UTC)
    if existing is not None:
        if existing.status == 'active':
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail='This student is already a verified member'
            )
        before = _membership_snapshot(existing)
        existing.status = 'active'
        existing.verified_by_id = actor.id
        existing.verified_at = now
        existing.revoked_at = None
        membership = existing
    else:
        before = None
        membership = ProgramMembership(
            user_id=target.id,
            program_id=program.id,
            status='active',
            verified_by_id=actor.id,
            verified_at=now,
        )
        db.add(membership)
        await db.flush()

    await record_audit(
        db,
        actor_id=actor.id,
        action='program_membership.verify',
        target_type='program_membership',
        target_id=membership.id,
        before_data=before,
        after_data=_membership_snapshot(membership),
    )
    await db.commit()
    await db.refresh(membership)

    profile = await get_profile_by_user_id(db, target.id)
    return membership, target, profile


async def revoke_membership(
    db: AsyncSession, *, actor: User, program: Program, user_id: UUID, reason: str | None
) -> ProgramMembership:
    membership = (
        await db.execute(
            select(ProgramMembership).where(
                ProgramMembership.user_id == user_id,
                ProgramMembership.program_id == program.id,
            )
        )
    ).scalar_one_or_none()
    if membership is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Membership not found')
    if membership.status != 'active':
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Only an active membership can be revoked')

    before = _membership_snapshot(membership)
    membership.status = 'revoked'
    membership.revoked_at = datetime.now(UTC)

    after = _membership_snapshot(membership)
    if reason:
        after['reason'] = reason.strip()

    await record_audit(
        db,
        actor_id=actor.id,
        action='program_membership.revoke',
        target_type='program_membership',
        target_id=membership.id,
        before_data=before,
        after_data=after,
    )
    await db.commit()
    await db.refresh(membership)
    return membership
