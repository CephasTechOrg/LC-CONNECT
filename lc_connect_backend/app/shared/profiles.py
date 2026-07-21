"""Shared profile read helpers (repository).

`profile_load_options` and `get_profile_by_user_id` are consumed by profiles,
connections, messages, and discovery. They live in the shared kernel so downstream
features never import the profiles feature directly.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import Profile, UserLanguage


def profile_load_options():
    return [
        selectinload(Profile.user),
        selectinload(Profile.interests),
        selectinload(Profile.looking_for_options),
        selectinload(Profile.languages).selectinload(UserLanguage.language),
    ]


async def get_profile_by_user_id(db: AsyncSession, user_id: UUID) -> Profile:
    profile = (await db.execute(select(Profile).options(*profile_load_options()).where(Profile.user_id == user_id))).scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Profile not found')
    return profile
