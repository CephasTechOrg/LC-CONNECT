"""Cross-feature DTOs.

`ProfilePublic` is the canonical public representation of a profile, consumed by the
profiles, connections, messages, and discovery features (and produced by
`app.shared.serializers.profile_to_public`). It lives in the shared kernel so those
features depend on shared rather than on each other.
"""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class ProfilePublic(BaseModel):
    id: UUID
    user_id: UUID
    display_name: str | None
    pronouns: str | None
    major: str | None
    class_year: int | None
    country_state: str | None
    campus: str | None
    bio: str | None
    avatar_url: str | None
    is_hidden: bool
    is_verified: bool
    profile_completed: bool
    interests: list[str]
    languages_spoken: list[str]
    languages_learning: list[str]
    looking_for: list[str]
    looking_for_codes: list[str]


# Safety report DTO. Shared because both safety and admin (moderation) return it.
class ReportRead(BaseModel):
    id: UUID
    reporter_id: UUID
    reported_user_id: UUID | None
    activity_id: UUID | None
    group_id: UUID | None = None
    message_id: UUID | None = None
    message_body: str | None = None  # evidence snapshot — survives deletion of the message/group
    reason: str
    details: str | None
    status: str
    created_at: datetime
