"""Cross-feature serializers.

`profile_to_public` renders a Profile ORM row into the public-facing schema. It is
used by the profiles, connections, messages, and discovery features, so it lives in
the shared kernel rather than any single feature.
"""

from __future__ import annotations

from app.models import Profile
from app.shared.schemas import ProfilePublic


def profile_to_public(profile: Profile) -> ProfilePublic:
    spoken = sorted([row.language.name for row in profile.languages if row.kind == 'speaks'])
    learning = sorted([row.language.name for row in profile.languages if row.kind == 'learning'])
    looking_options = sorted(profile.looking_for_options, key=lambda item: item.name)
    return ProfilePublic(
        id=profile.id,
        user_id=profile.user_id,
        display_name=profile.display_name,
        pronouns=profile.pronouns,
        major=profile.major,
        class_year=profile.class_year,
        country_state=profile.country_state,
        campus=profile.campus,
        bio=profile.bio,
        avatar_url=profile.avatar_url,
        is_hidden=profile.is_hidden,
        is_verified=profile.user.is_verified,
        profile_completed=profile.profile_completed,
        interests=sorted([interest.name for interest in profile.interests]),
        languages_spoken=spoken,
        languages_learning=learning,
        looking_for=[item.name for item in looking_options],
        looking_for_codes=[item.code for item in looking_options],
    )
