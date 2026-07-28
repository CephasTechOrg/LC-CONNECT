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
    # Staff identity. `role` lets the client pick the staff vs student layout. A staff member's
    # email is public contact info (a professor expects to be reached) — students' stays null.
    # Position context is filled only on the single-profile view (kept off list serializations).
    role: str = 'student'
    contact_email: str | None = None
    position_title: str | None = None
    position_department: str | None = None
    position_office: str | None = None
    position_availability: str | None = None


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
