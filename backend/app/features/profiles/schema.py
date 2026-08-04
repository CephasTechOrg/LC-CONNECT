from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints

from app.shared.schemas import ProfilePublic

# Interests/languages are *get-or-create*: an unrecognised name inserts a new row into the shared
# `interests`/`languages` tables, which feed the PUBLIC `/lookups` list every user sees during
# onboarding. Unbounded, that let any signed-in student (a) issue one query+insert per item, so a
# single request could hammer the database, and (b) inject arbitrary entries into a global,
# user-visible vocabulary. Both caps below exist to close that.
#
# 80 chars matches the `String(80)` columns — longer previously reached the database and failed
# there as an opaque error instead of a clean 422.
_LookupName = Annotated[str, StringConstraints(min_length=1, max_length=80, strip_whitespace=True)]
_MAX_LOOKUP_ITEMS = 30


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
    interests: list[_LookupName] | None = Field(default=None, max_length=_MAX_LOOKUP_ITEMS)
    languages_spoken: list[_LookupName] | None = Field(default=None, max_length=_MAX_LOOKUP_ITEMS)
    languages_learning: list[_LookupName] | None = Field(default=None, max_length=_MAX_LOOKUP_ITEMS)
    looking_for_codes: list[_LookupName] | None = Field(default=None, max_length=_MAX_LOOKUP_ITEMS)


class MyProfileRead(ProfilePublic):
    allow_messages_from_matches_only: bool
    show_profile_to_verified_only: bool
    connection_count: int
    activity_count: int
    message_count: int
    campus_position_status: str | None = None
    campus_position_title: str | None = None
    campus_position_verified: bool = False
