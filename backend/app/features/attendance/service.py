"""Honors attendance business logic — session/QR/check-in in Phase 2."""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Program
from app.shared.programs import PRESIDENTIAL_SCHOLARS_SLUG


async def get_honors_program_id(db: AsyncSession) -> UUID | None:
    """Resolve the Honors (`presidential_scholars`) program row — seeded at deploy time."""
    return (
        await db.execute(
            select(Program.id).where(Program.slug == PRESIDENTIAL_SCHOLARS_SLUG, Program.is_active.is_(True))
        )
    ).scalar_one_or_none()
