from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Interest, Language, LookingForOption

# Starting vocabulary only. Students may type their own — `profiles.service.get_or_create_*`
# inserts anything unrecognised — so this list exists to make the common choices one tap away,
# not to be exhaustive. Kept deliberately short for that reason: a wall of chips is harder to
# scan than a handful plus a text field.
DEFAULT_INTERESTS = [
    ('Basketball', 'sports'), ('Soccer', 'sports'), ('Football', 'sports'),
    ('Track & Field', 'sports'), ('Chess', 'games'), ('Gaming', 'social'),
    ('Coding', 'academic'), ('Data Science', 'academic'), ('Biology', 'academic'),
    ('Business', 'academic'), ('Entrepreneurship', 'academic'), ('Debate', 'academic'),
    ('Music', 'creative'), ('Photography', 'creative'), ('Art', 'creative'),
    ('Dance', 'creative'), ('Fashion', 'creative'), ('Writing', 'creative'),
    ('Volunteering', 'campus'), ('Church', 'community'), ('Cultural Exchange', 'community'),
    ('Coffee', 'social'), ('Cooking', 'social'), ('Movies', 'social'),
    ('Fitness', 'wellness'), ('Hiking', 'outdoors'), ('Travel', 'outdoors'),
    ('Reading', 'quiet'),
]

DEFAULT_LANGUAGES = [
    'English', 'Spanish', 'French', 'Portuguese', 'Mandarin', 'Arabic', 'German', 'Italian',
    'Russian', 'Ukrainian', 'Korean', 'Japanese', 'Hindi',
    'Twi', 'Yoruba', 'Igbo', 'Hausa', 'Swahili', 'Amharic',
    'American Sign Language',
]

# Labelled "I'm open to" in the app. Campus-shaped on purpose: the old set ("Looking for", with
# "Open Connection") read like a dating app rather than a student platform.
DEFAULT_LOOKING_FOR = [
    ('friendship', 'Friendship'),
    ('study_partner', 'Study partner'),
    ('language_exchange', 'Language exchange'),
    ('events', 'Campus events'),
    ('clubs_orgs', 'Clubs & organisations'),
    ('research_projects', 'Research or projects'),
    ('career_advice', 'Career advice'),
]

# Removed from the offered set. The migration clears any selections that referenced them.
RETIRED_LOOKING_FOR = ['open_connection']


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
        option = (
            await db.execute(select(LookingForOption).where(LookingForOption.code == code))
        ).scalar_one_or_none()
        if option is None:
            db.add(LookingForOption(code=code, name=name))
        elif option.name != name:
            # Renames matter here: 'Events' -> 'Campus events' has to reach a database that was
            # seeded before the wording changed, and inserting-only would never update it.
            option.name = name

    await db.commit()
