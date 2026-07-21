from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.shared.schemas import ProfilePublic


class ConnectionRequestCreate(BaseModel):
    receiver_id: UUID
    intent: str | None = Field(default=None, max_length=50)
    note: str | None = Field(default=None, max_length=240)


class ConnectionRequestRead(BaseModel):
    id: UUID
    sender_id: UUID
    receiver_id: UUID
    intent: str | None
    note: str | None
    status: str
    created_at: datetime


class ConnectionRequestEnriched(BaseModel):
    id: UUID
    sender_id: UUID
    receiver_id: UUID
    intent: str | None
    note: str | None
    status: str
    created_at: datetime
    partner_profile: ProfilePublic | None = None


class MatchRead(BaseModel):
    id: UUID
    user_a_id: UUID
    user_b_id: UUID
    created_at: datetime
    partner: ProfilePublic | None = None
