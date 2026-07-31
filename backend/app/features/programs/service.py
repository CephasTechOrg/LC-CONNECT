"""Student-facing program membership reads (Blueprint Bond foundation).

Membership itself is never self-service — an Honors admin verifies from an official roster
(see `app/features/admin/programs.py`). This module only exposes the read side.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Program, ProgramMembership


async def list_active_memberships(db: AsyncSession, user_id: UUID) -> list[tuple[ProgramMembership, Program]]:
    """Every program this user is currently an active member of (e.g. Presidential Scholars) —
    drives Blueprint Bond surfaces in Profile/Campus Hub on the client."""
    rows = await db.execute(
        select(ProgramMembership, Program)
        .join(Program, Program.id == ProgramMembership.program_id)
        .where(ProgramMembership.user_id == user_id, ProgramMembership.status == 'active')
    )
    return list(rows.all())
