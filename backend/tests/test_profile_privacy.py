"""Locks the student-email privacy rule in `profile_to_public`.

That one line decides whether every student's email address is exposed to every other student —
`profile_to_public` feeds discovery, connections, messages, and groups, so a regression there
leaks the whole directory at once. It had no test until this hardening pass.
"""

from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.shared.serializers import profile_to_public


def _profile(role: str, email: str = 'person@livingstone.edu'):
    """A stand-in Profile with just the attributes the serializer reads."""
    return SimpleNamespace(
        id=uuid4(),
        user_id=uuid4(),
        display_name='Amara',
        pronouns=None,
        major=None,
        class_year=None,
        country_state=None,
        campus=None,
        bio=None,
        avatar_url=None,
        is_hidden=False,
        profile_completed=True,
        interests=[],
        languages=[],
        looking_for_options=[],
        user=SimpleNamespace(email=email, role=role, is_verified=True),
    )


def test_student_email_is_never_exposed():
    result = profile_to_public(_profile('student', 'student@students.livingstone.edu'))
    assert result.contact_email is None


def test_staff_email_is_exposed_as_public_contact_info():
    """A professor expects to be reachable — this is deliberate, not a leak."""
    result = profile_to_public(_profile('staff', 'prof@livingstone.edu'))
    assert result.contact_email == 'prof@livingstone.edu'


def test_admin_email_is_exposed():
    result = profile_to_public(_profile('admin', 'admin@livingstone.edu'))
    assert result.contact_email == 'admin@livingstone.edu'


@pytest.mark.parametrize('role', ['student', 'employer', 'alumni', '', 'STAFF', 'Staff', 'unknown'])
def test_anything_not_exactly_staff_or_admin_is_treated_as_private(role):
    """Fails closed: an unrecognised or oddly-cased role must never leak an address. Casing
    matters because the check is an exact membership test, not a case-insensitive one."""
    result = profile_to_public(_profile(role, 'someone@livingstone.edu'))
    assert result.contact_email is None


def test_public_profile_carries_no_other_account_fields():
    """The public shape must expose profile data only — never account internals like the auth id,
    password hash, or account status."""
    result = profile_to_public(_profile('student'))
    forbidden = {'email', 'auth_user_id', 'status', 'is_active'}
    assert forbidden.isdisjoint(result.model_fields.keys())
