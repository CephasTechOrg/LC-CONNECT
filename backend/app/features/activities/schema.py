from datetime import datetime
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field, model_validator


class ActivityCreate(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    category: str = Field(max_length=40)
    location: str = Field(min_length=2, max_length=160)
    # `AwareDatetime`, not `datetime`: a naive value has no defined instant, and accepting one let
    # it reach a `timestamptz` column to be silently reinterpreted in the session timezone. It also
    # made the ordering check in `update_activity` compare naive against aware and raise a 500.
    # Every client already sends an offset (`toUtc().toIso8601String()`), so this only rejects
    # payloads that were never well-defined.
    start_time: AwareDatetime
    end_time: AwareDatetime | None = None
    max_participants: int | None = Field(default=None, ge=2, le=500)

    @model_validator(mode='after')
    def validate_times(self):
        if self.end_time and self.end_time <= self.start_time:
            raise ValueError('end_time must be after start_time')
        return self


class ActivityUpdate(BaseModel):
    """Partial edit — only supplied fields change (creator-only)."""

    title: str | None = Field(default=None, min_length=3, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    category: str | None = Field(default=None, max_length=40)
    location: str | None = Field(default=None, min_length=2, max_length=160)
    # See `ActivityCreate`. This model is where the naive/aware mix actually bit: a PATCH carrying
    # only a naive `end_time` reached `update_activity`, which compares it against the stored
    # (aware) `start_time` — an unhandled `TypeError`, surfacing as a 500.
    start_time: AwareDatetime | None = None
    end_time: AwareDatetime | None = None
    max_participants: int | None = Field(default=None, ge=2, le=500)


class ActivityParticipantRead(BaseModel):
    """A row in an activity's roster. Activities are public, so this is just names/avatars —
    no moderation. `is_creator` marks the organizer."""

    user_id: UUID
    profile_id: UUID | None
    display_name: str | None
    avatar_url: str | None
    campus_verified: bool
    is_creator: bool


class ActivityRead(BaseModel):
    id: UUID
    creator_id: UUID
    title: str
    description: str | None
    category: str
    location: str
    banner_url: str | None
    start_time: datetime
    end_time: datetime | None
    max_participants: int | None
    participant_count: int
    has_joined: bool
    is_cancelled: bool
    created_at: datetime
