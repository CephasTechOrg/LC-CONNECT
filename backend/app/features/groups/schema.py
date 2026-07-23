from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

from app.shared.schemas import ProfilePublic

Category = Literal['club', 'housing', 'class', 'interest']
Visibility = Literal['public', 'unlisted', 'private']
JoinPolicy = Literal['open', 'approval', 'invite']


class GroupCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    category: Category
    visibility: Visibility = 'public'
    join_policy: JoinPolicy = 'approval'
    description: str | None = Field(default=None, max_length=2000)
    max_members: int | None = Field(default=None, ge=2, le=5000)


class GroupUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    description: str | None = Field(default=None, max_length=2000)
    category: Category | None = None
    visibility: Visibility | None = None
    join_policy: JoinPolicy | None = None
    max_members: int | None = Field(default=None, ge=2, le=5000)


class GroupSummary(BaseModel):
    id: UUID
    name: str
    avatar_url: str | None
    category: str
    visibility: str
    join_policy: str
    member_count: int
    max_members: int | None
    my_status: str | None  # None | requested | invited | active | banned


class GroupRead(GroupSummary):
    description: str | None
    owner_id: UUID
    conversation_id: UUID
    my_role: str | None  # None | member | admin | owner
    created_at: datetime


class GroupMemberRead(BaseModel):
    user_id: UUID
    profile: ProfilePublic | None
    role: str
    status: str
    joined_at: datetime


class JoinResult(BaseModel):
    """`active` = joined an open group; `requested` = awaiting admin approval."""

    status: Literal['active', 'requested']
    group_id: UUID
