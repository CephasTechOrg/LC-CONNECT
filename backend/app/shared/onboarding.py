"""Role-aware onboarding completion rules (Campus Hub Phase 2)."""

from __future__ import annotations

from app.models import CampusPosition, Profile, User

CAMPUS_CATEGORIES = frozenset(
    {'academic', 'advising', 'residential_life', 'campus_services', 'campus_safety'}
)


def compute_student_profile_completed(profile: Profile) -> bool:
    return bool(profile.display_name and profile.major and profile.class_year and profile.looking_for_options)


def compute_staff_onboarding_completed(profile: Profile, position: CampusPosition | None) -> bool:
    if position is None:
        return False
    return bool(
        profile.display_name
        and position.category in CAMPUS_CATEGORIES
        and position.official_title
        and position.department
    )


def compute_onboarding_completed(
    user: User,
    profile: Profile,
    position: CampusPosition | None = None,
) -> bool:
    if user.role == 'admin':
        return True
    if user.role == 'staff':
        return compute_staff_onboarding_completed(profile, position)
    return compute_student_profile_completed(profile)
