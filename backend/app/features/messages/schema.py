from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.shared.schemas import ProfilePublic


class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    # Optional idempotency key; a retry with the same value returns the original message.
    client_message_id: UUID | None = None


class MessageRead(BaseModel):
    id: UUID
    match_id: UUID
    sender_id: UUID
    client_message_id: UUID | None = None
    body: str
    created_at: datetime
    read_at: datetime | None


class MessageThreadRead(BaseModel):
    match_id: UUID
    partner: ProfilePublic | None
    latest_message: MessageRead | None
