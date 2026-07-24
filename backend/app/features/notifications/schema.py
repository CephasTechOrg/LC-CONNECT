from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class DeviceRegister(BaseModel):
    token: str = Field(min_length=1, max_length=512)
    platform: Literal['ios', 'android', 'web']


class NotificationActor(BaseModel):
    id: UUID
    display_name: str | None = None
    avatar_url: str | None = None


class NotificationGroupInfo(BaseModel):
    id: UUID
    name: str


class NotificationRead(BaseModel):
    """A single in-app notification. Structured (type + group + actor); the client renders the
    sentence, so renamed groups/people always read correctly."""

    id: UUID
    type: str
    read: bool
    created_at: datetime
    group: NotificationGroupInfo | None = None
    actor: NotificationActor | None = None


class UnreadCount(BaseModel):
    count: int
