from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Interest, Language, LookingForOption

DEFAULT_INTERESTS = [
    ('Basketball', 'sports'), ('Soccer', 'sports'), ('Coding', 'academic'), ('Data Science', 'academic'),
    ('Biology', 'academic'), ('Business', 'academic'), ('Music', 'creative'), ('Photography', 'creative'),
    ('Volunteering', 'campus'), ('Coffee', 'social'), ('Fitness', 'wellness'), ('Gaming', 'social'),
    ('Church', 'community'), ('Hiking', 'outdoors'),
]

DEFAULT_LANGUAGES = ['English', 'Spanish', 'French', 'Mandarin', 'Arabic', 'Twi', 'Yoruba', 'Ukrainian', 'Russian', 'German']

DEFAULT_LOOKING_FOR = [
    ('friendship', 'Friendship'),
    ('study_partner', 'Study Partner'),
    ('language_exchange', 'Language Exchange'),
    ('events', 'Events'),
    ('open_connection', 'Open Connection'),
]


async def seed_lookup_data(db: AsyncSession) -> None:
    for name, category in DEFAULT_INTERESTS:
        existing = await db.execute(select(Interest).where(Interest.name == name))
        if existing.scalar_one_or_none() is None:
            db.add(Interest(name=name, category=category))

    for name in DEFAULT_LANGUAGES:
        existing = await db.execute(select(Language).where(Language.name == name))
        if existing.scalar_one_or_none() is None:
            db.add(Language(name=name))

    for code, name in DEFAULT_LOOKING_FOR:
        existing = await db.execute(select(LookingForOption).where(LookingForOption.code == code))
        if existing.scalar_one_or_none() is None:
            db.add(LookingForOption(code=code, name=name))

    await db.commit()
