"""Role-aware onboarding completion rules."""

from __future__ import annotations

from types import SimpleNamespace

from app.shared.onboarding import (
    compute_onboarding_completed,
    compute_staff_onboarding_completed,
    compute_student_profile_completed,
)


def _profile(**kwargs):
    base = {
        'display_name': None,
        'major': None,
        'class_year': None,
        'looking_for_options': [],
    }
    base.update(kwargs)
    return SimpleNamespace(**base)


def _position(**kwargs):
    base = {
        'category': 'academic',
        'official_title': None,
        'department': None,
    }
    base.update(kwargs)
    return SimpleNamespace(**base)


def test_student_completion_unchanged() -> None:
    profile = _profile(
        display_name='Alex',
        major='Biology',
        class_year=2026,
        looking_for_options=['friendship'],
    )
    assert compute_student_profile_completed(profile) is True


def test_student_incomplete_without_looking_for() -> None:
    profile = _profile(display_name='Alex', major='Biology', class_year=2026)
    assert compute_student_profile_completed(profile) is False


def test_staff_completion_requires_position_fields() -> None:
    user = SimpleNamespace(role='staff')
    profile = _profile(display_name='Dr. Lee')
    position = _position(official_title='Professor', department='Biology')
    assert compute_staff_onboarding_completed(profile, position) is True
    assert compute_onboarding_completed(user, profile, position) is True


def test_staff_incomplete_without_position() -> None:
    user = SimpleNamespace(role='staff')
    profile = _profile(display_name='Dr. Lee')
    assert compute_onboarding_completed(user, profile, None) is False


def test_admin_always_complete() -> None:
    user = SimpleNamespace(role='admin')
    profile = _profile()
    assert compute_onboarding_completed(user, profile, None) is True
