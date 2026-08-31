"""Honors attendance authorization — reuses ProgramMembership and honors_admin scope."""

from __future__ import annotations

from fastapi import Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_verified_connect_student
from app.features.admin import admins as admins_admin
from app.models import User
from app.shared.programs import PRESIDENTIAL_SCHOLARS_SLUG, is_active_program_member

_honors_admin_gate = admins_admin.require_admin_scope('honors_admin')


def honors_attendance_enabled() -> bool:
    return settings.honors_attendance_enabled


def ensure_honors_attendance_enabled() -> None:
    """Hide the feature entirely when the flag is off (404, not 403)."""
    if not honors_attendance_enabled():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Honors attendance is not enabled')


async def is_honors_student(db: AsyncSession, user_id) -> bool:
    return await is_active_program_member(db, user_id, PRESIDENTIAL_SCHOLARS_SLUG)


async def require_honors_student(
    current_user: User = Depends(require_verified_connect_student),
    db: AsyncSession = Depends(get_db),
) -> User:
    ensure_honors_attendance_enabled()
    if not await is_honors_student(db, current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='This attendance session is not available for your account',
        )
    return current_user


async def require_honors_attendance_admin(
    actor: User = Depends(_honors_admin_gate),
) -> User:
    ensure_honors_attendance_enabled()
    return actor
