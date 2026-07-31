"""Shared program-membership check.

Used by the scholars feature (gating the professional profile) and by campus_hub (gating
Blueprint Bond-only opportunity posts) — lives here, not inside either feature's `service.py`, so
neither feature ends up importing the other's service module.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Program, ProgramMembership

# The one program that exists today (seeded by migration 5f045e1e9b50) — Blueprint Bond surfaces
# (the scholar professional profile, employer-opportunity eligibility) key off this.
PRESIDENTIAL_SCHOLARS_SLUG = 'presidential_scholars'


async def is_active_program_member(db: AsyncSession, user_id: UUID, program_slug: str) -> bool:
    row = (
        await db.execute(
            select(ProgramMembership.id)
            .join(Program, Program.id == ProgramMembership.program_id)
            .where(
                ProgramMembership.user_id == user_id,
                ProgramMembership.status == 'active',
                Program.slug == program_slug,
            )
        )
    ).scalar_one_or_none()
    return row is not None
