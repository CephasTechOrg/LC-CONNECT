from uuid import UUID

from pydantic import BaseModel


class DiscoveryCard(BaseModel):
    profile_id: UUID
    user_id: UUID
    display_name: str | None
    avatar_url: str | None
    major: str | None
    class_year: int | None
    bio: str | None
    is_verified: bool
    interests: list[str]
    languages_spoken: list[str]
    languages_learning: list[str]
    looking_for: list[str]
    looking_for_codes: list[str]
    match_score: int
    match_reasons: list[str]
