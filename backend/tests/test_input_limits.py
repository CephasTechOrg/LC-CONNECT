"""Bounds on client-supplied collections and free-text.

`interests` / `languages_*` are **get-or-create**: an unrecognised name inserts a row into the
shared `interests`/`languages` tables that feed the PUBLIC `/lookups` list. Unbounded, any signed-in
student could issue one query+insert per item (hammering the database from a single request) and
inject arbitrary entries into a vocabulary every other user sees during onboarding.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.features.campus_hub.schema import CampusResourceCreate
from app.features.profiles.schema import ProfileUpdate

# Two different caps, for two different reasons.
#
#   _MAX_SELECTIONS (5)   a product rule on what a student may choose — five is enough to say who
#                         you are, and few enough that the answers stay meaningful.
#   _MAX_LOOKUP_ITEMS (30) the abuse ceiling described above, still guarding `looking_for_codes`.
_SELECTION_FIELDS = ['interests', 'languages_spoken', 'languages_learning']


@pytest.mark.parametrize('field', _SELECTION_FIELDS)
def test_a_student_may_choose_five(field):
    payload = ProfileUpdate(**{field: [f'Item {i}' for i in range(5)]})
    assert len(getattr(payload, field)) == 5


@pytest.mark.parametrize('field', _SELECTION_FIELDS)
def test_a_sixth_selection_is_refused(field):
    with pytest.raises(ValidationError):
        ProfileUpdate(**{field: [f'Item {i}' for i in range(6)]})


@pytest.mark.parametrize('field', [*_SELECTION_FIELDS, 'looking_for_codes'])
def test_every_lookup_list_is_capped(field):
    """All four write to shared/lookup vocabularies — none may be left unbounded."""
    with pytest.raises(ValidationError):
        ProfileUpdate(**{field: [f'x{i}' for i in range(31)]})


@pytest.mark.parametrize('field', ['interests', 'languages_spoken', 'languages_learning', 'looking_for_codes'])
def test_individual_lookup_names_are_length_capped(field):
    """80 matches the String(80) columns — longer used to reach the database and fail there as an
    opaque error rather than a clean 422."""
    with pytest.raises(ValidationError):
        ProfileUpdate(**{field: ['a' * 81]})


def test_lookup_names_are_whitespace_stripped():
    payload = ProfileUpdate(interests=['  Chess  '])
    assert payload.interests == ['Chess']


def test_blank_lookup_name_is_rejected():
    with pytest.raises(ValidationError):
        ProfileUpdate(interests=['   '])


def test_normal_profile_update_still_works():
    """The caps must not disturb ordinary use."""
    payload = ProfileUpdate(
        display_name='Amara',
        interests=['Chess', 'Robotics'],
        languages_spoken=['English', 'Twi'],
        looking_for_codes=['study_partner'],
    )
    assert payload.interests == ['Chess', 'Robotics']


def test_campus_resource_description_is_capped():
    base = dict(category='academics', title='Writing Center')
    with pytest.raises(ValidationError):
        CampusResourceCreate(**base, description='x' * 4001)


def test_campus_resource_normal_description_accepted():
    r = CampusResourceCreate(category='academics', title='Writing Center', description='Drop-in help.')
    assert r.description == 'Drop-in help.'
