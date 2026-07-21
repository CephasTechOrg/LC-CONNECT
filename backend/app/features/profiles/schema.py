from pydantic import BaseModel, Field

from app.shared.schemas import ProfilePublic


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=120)
    pronouns: str | None = Field(default=None, max_length=50)
    major: str | None = Field(default=None, max_length=120)
    class_year: int | None = Field(default=None, ge=1900, le=2100)
    country_state: str | None = Field(default=None, max_length=120)
    campus: str | None = Field(default=None, max_length=120)
    bio: str | None = Field(default=None, max_length=500)
    is_hidden: bool | None = None
    allow_messages_from_matches_only: bool | None = None
    show_profile_to_verified_only: bool | None = None
    interests: list[str] | None = None
    languages_spoken: list[str] | None = None
    languages_learning: list[str] | None = None
    looking_for_codes: list[str] | None = None


class MyProfileRead(ProfilePublic):
    allow_messages_from_matches_only: bool
    show_profile_to_verified_only: bool
    connection_count: int
    activity_count: int
    message_count: int
