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
    # What tapping this row should open, when `group` and `actor` cannot say — e.g.
    # `('attendance_session', <uuid>)`. Null for rows whose target is already the group or actor.
    # The client treats an unknown `target_type` as "no target" and opens the inbox, so a new type
    # added server-side cannot break an older client.
    target_type: str | None = None
    target_id: UUID | None = None
    #: Short display token for this event — currently the reaction emoji. See the model.
    detail: str | None = None


class UnreadCount(BaseModel):
    count: int
