from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.features.campus_positions.schema import CampusPositionRead
from app.features.programs.schema import ProgramMembershipRead


class AdminUserRead(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_active: bool
    is_verified: bool
    display_name: str | None = None


class SuspendUserRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=240)


class PositionReviewRequest(BaseModel):
    review_note: str | None = Field(default=None, max_length=500)


class PositionRevokeRequest(PositionReviewRequest):
    # Off by default: a position usually ends because a term ended, and the notices that person
    # published are still legitimate. Opt in when the position was fraudulent or abused.
    archive_posts: bool = Field(default=False)


class CampusPositionAdminRead(CampusPositionRead):
    user_email: EmailStr
    user_role: str
    display_name: str | None = None


class ProgramMembershipVerifyRequest(BaseModel):
    email: EmailStr


class ProgramMembershipRevokeRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=500)


class ProgramMembershipAdminRead(ProgramMembershipRead):
    user_email: EmailStr
    display_name: str | None = None


class CampusPostAdminRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    author_id: UUID
    kind: str
    title: str
    summary: str | None
    body: str
    audience: str
    category: str | None
    priority: str
    status: str
    publish_at: datetime | None
    expires_at: datetime | None
    external_url: str | None
    created_at: datetime
    updated_at: datetime


class CampusResourceAdminRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    category: str
    title: str
    description: str
    location: str | None
    hours: str | None
    contact_email: EmailStr | None
    phone: str | None
    external_url: str | None
    sort_order: int
    is_active: bool
    updated_by_id: UUID | None
    created_at: datetime
    updated_at: datetime
