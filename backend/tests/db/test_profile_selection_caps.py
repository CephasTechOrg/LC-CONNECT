"""The five-item cap, custom entries, and the retired looking-for option."""

from __future__ import annotations

import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.features.profiles.schema import ProfileUpdate
from app.features.profiles.service import get_or_create_interests, get_or_create_languages
from app.models import Interest, LookingForOption
from app.seed import DEFAULT_LOOKING_FOR, RETIRED_LOOKING_FOR, seed_lookup_data

# ── the cap ───────────────────────────────────────────────────────────────────

@pytest.mark.parametrize('field', ['interests', 'languages_spoken', 'languages_learning'])
def test_five_selections_are_allowed(field):
    payload = ProfileUpdate(**{field: ['One', 'Two', 'Three', 'Four', 'Five']})
    assert len(getattr(payload, field)) == 5


@pytest.mark.parametrize('field', ['interests', 'languages_spoken', 'languages_learning'])
def test_a_sixth_selection_is_rejected(field):
    """Enforced server-side as well as in the app, so it holds whatever the client sends."""
    with pytest.raises(ValidationError):
        ProfileUpdate(**{field: ['One', 'Two', 'Three', 'Four', 'Five', 'Six']})


# ── custom entries ────────────────────────────────────────────────────────────

async def test_a_student_can_add_an_interest_that_does_not_exist(db):
    """The seeded list is a starting point, not the whole vocabulary."""
    items = await get_or_create_interests(db, ['Afrobeats'])
    await db.commit()
    assert [i.name for i in items] == ['Afrobeats']
    assert items[0].category == 'custom'


async def test_custom_entries_do_not_duplicate_an_existing_one(db):
    """Two students typing the same thing must land on one row, or the shared vocabulary fills
    with near-identical chips."""
    await get_or_create_interests(db, ['Chess'])
    await db.commit()
    again = await get_or_create_interests(db, ['  chess  '])
    await db.commit()
    rows = (await db.execute(select(Interest).where(Interest.name == 'Chess'))).scalars().all()
    assert len(rows) == 1
    assert again[0].id == rows[0].id


async def test_custom_languages_work_the_same_way(db):
    first = await get_or_create_languages(db, ['Ewe'])
    await db.commit()
    second = await get_or_create_languages(db, ['ewe'])
    await db.commit()
    assert first[0].id == second[0].id


# ── the looking-for set ───────────────────────────────────────────────────────

async def test_seeding_installs_the_campus_shaped_options(db):
    await seed_lookup_data(db)
    names = {
        o.code: o.name
        for o in (await db.execute(select(LookingForOption))).scalars().all()
    }
    assert names['events'] == 'Campus events'
    assert 'clubs_orgs' in names
    assert 'career_advice' in names


async def test_reseeding_renames_an_option_rather_than_leaving_it_stale(db):
    """Seeding used to insert-only, so a database seeded before the wording changed would have
    kept 'Events' forever."""
    db.add(LookingForOption(code='events', name='Events'))
    await db.commit()

    await seed_lookup_data(db)

    option = (
        await db.execute(select(LookingForOption).where(LookingForOption.code == 'events'))
    ).scalar_one()
    assert option.name == 'Campus events'


def test_open_connection_is_no_longer_offered():
    """It meant nothing concrete, and alongside the old "Looking for" label it made a student
    platform read like a dating app."""
    codes = {code for code, _ in DEFAULT_LOOKING_FOR}
    assert 'open_connection' not in codes
    assert 'open_connection' in RETIRED_LOOKING_FOR
