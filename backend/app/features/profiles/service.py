"""Profiles domain logic: lookups upsert and completion rule.

Shared profile reads (`get_profile_by_user_id`, `profile_load_options`) live in
`app.shared.profiles` because other features need them too; this module holds the
write-side helpers that are specific to editing a profile.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Interest, Language, LookingForOption, Profile


async def get_or_create_interests(db: AsyncSession, names: list[str]) -> list[Interest]:
    items: list[Interest] = []
    for name in sorted({name.strip().title() for name in names if name.strip()}):
        item = (await db.execute(select(Interest).where(Interest.name == name))).scalar_one_or_none()
        if item is None:
            item = Interest(name=name, category='custom')
            db.add(item)
            await db.flush()
        items.append(item)
    return items


async def get_or_create_languages(db: AsyncSession, names: list[str]) -> list[Language]:
    items: list[Language] = []
    for name in sorted({name.strip().title() for name in names if name.strip()}):
        item = (await db.execute(select(Language).where(Language.name == name))).scalar_one_or_none()
        if item is None:
            item = Language(name=name)
            db.add(item)
            await db.flush()
        items.append(item)
    return items


async def get_looking_for_options(db: AsyncSession, codes: list[str]) -> list[LookingForOption]:
    clean_codes = sorted({code.strip().lower() for code in codes if code.strip()})
    return list((await db.execute(select(LookingForOption).where(LookingForOption.code.in_(clean_codes)))).scalars().all())


def compute_profile_completed(profile: Profile) -> bool:
    return bool(profile.display_name and profile.major and profile.class_year and profile.looking_for_options)
