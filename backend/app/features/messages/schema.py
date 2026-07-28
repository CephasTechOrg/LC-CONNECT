from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field

from app.shared.schemas import ProfilePublic


class MessageCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    # Optional idempotency key; a retry with the same value returns the original message.
    client_message_id: UUID | None = None


class StaffThreadCreate(BaseModel):
    """Start (or resolve) a staff↔anyone conversation — no connection required."""

    target_user_id: UUID


class MessageRead(BaseModel):
    id: UUID
    # match_id is null for group messages (a group has no match); conversation_id is the
    # universal container. Clients address a thread by match_id (DM) or conversation_id (group).
    match_id: UUID | None = None
    conversation_id: UUID | None = None
    sender_id: UUID
    client_message_id: UUID | None = None
    body: str  # empty when deleted — the original is never sent to clients
    created_at: datetime
    read_at: datetime | None
    deleted: bool = False


class GroupThreadInfo(BaseModel):
    id: UUID
    name: str
    avatar_url: str | None


class MessageThreadRead(BaseModel):
    # `conversation_id` is the universal addressing id (what the client opens/subscribes to).
    # `match_id` is kept for DM back-compat (null for groups and staff_dm). Clients branch on
    # `kind`.
    conversation_id: UUID
    kind: str  # 'dm' | 'group' | 'staff_dm'
    match_id: UUID | None = None
    partner: ProfilePublic | None = None  # dm / staff_dm only
    # Staff identity context for the partner, when they hold a verified campus position —
    # lets a student see *who* is messaging them (e.g. "Officer Jane Doe · Campus Security").
    partner_position_title: str | None = None
    partner_department: str | None = None
    group: GroupThreadInfo | None = None  # group only
    latest_message: MessageRead | None


class UnreadSummary(BaseModel):
    """Total unread + per-conversation counts (conversations with 0 unread are omitted)."""

    total: int
    per_conversation: dict[UUID, int]


class RecipientSearchResult(BaseModel):
    """A lightweight, message-composer-facing user match (not the full profile)."""

    user_id: UUID
    display_name: str | None
    avatar_url: str | None
    role: str
    position_title: str | None = None
    department: str | None = None


class MessagingCapabilities(BaseModel):
    can_message_anyone: bool
    staff_messaging_enabled: bool
