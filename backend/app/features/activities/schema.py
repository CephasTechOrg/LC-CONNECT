from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ActivityCreate(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    category: str = Field(max_length=40)
    location: str = Field(min_length=2, max_length=160)
    start_time: datetime
    end_time: datetime | None = None
    max_participants: int | None = Field(default=None, ge=2, le=500)

    @model_validator(mode='after')
    def validate_times(self):
        if self.end_time and self.end_time <= self.start_time:
            raise ValueError('end_time must be after start_time')
        return self


class ActivityRead(BaseModel):
    id: UUID
    creator_id: UUID
    title: str
    description: str | None
    category: str
    location: str
    start_time: datetime
    end_time: datetime | None
    max_participants: int | None
    participant_count: int
    has_joined: bool
    is_cancelled: bool
    created_at: datetime
