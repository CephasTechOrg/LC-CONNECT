from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.features.campus_positions.schema import CampusPositionRead
from app.features.employers.schema import EmployerOrganizationRead, OpportunitySubmissionRead
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
    """Moderator must record why the account was suspended (stored on the audit trail)."""

    reason: str = Field(min_length=1, max_length=240)


class ResolveReportRequest(BaseModel):
    note: str | None = Field(default=None, max_length=500)


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


class InviteAdminRequest(BaseModel):
    email: EmailStr
    role: str


class AdminMembershipRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    role: str
    status: str
    invited_at: datetime
    revoked_at: datetime | None
    user_email: EmailStr
    display_name: str | None = None


class MyAdminScopesRead(BaseModel):
    scopes: list[str]


class AdminDashboardSummary(BaseModel):
    """The dashboard's KPI-card payload. Honors-Program fields are `None` for an admin without
    `honors_admin` scope — the dashboard shows fewer cards rather than a fabricated zero."""

    total_users: int
    open_reports: int
    pending_positions: int
    active_scholars: int | None = None
    employer_partners: int | None = None
    active_opportunities: int | None = None
    pending_employer_approvals: int | None = None
    pending_opportunity_reviews: int | None = None


ServiceStatus = Literal['operational', 'down']


class SystemStatusRead(BaseModel):
    """Every field is the result of a real check made at request time (`app/features/admin/system_status.py`)
    — never a hardcoded 'operational'. No separate "Email" entry: Supabase Auth sends invite
    emails itself, there's no distinct email provider in this codebase to check independently."""

    api_gateway: ServiceStatus
    database: ServiceStatus
    auth: ServiceStatus
    storage: ServiceStatus
    websocket_connections: int = Field(
        ge=0,
        description='Live WebSocket connections on this API process (per-instance).',
    )


class EmployerRejectRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=500)


class EmployerOrganizationAdminRead(EmployerOrganizationRead):
    contact_email: EmailStr
    contact_name: str | None = None
    review_note: str | None = None


class OpportunitySubmissionRejectRequest(BaseModel):
    # Required (not optional): rejecting a submission must always record why, so the employer
    # portal can show the employer a real reason, not just a boolean flip.
    reason: str = Field(min_length=1, max_length=500)


class OpportunitySubmissionAdminRead(OpportunitySubmissionRead):
    organization_id: UUID
    organization_name: str
    # Employer posts now publish immediately, so moderation is reactive: an admin needs the
    # published post's id to take it down without hunting for it in the Campus Hub content list.
    published_post_id: UUID | None = None
    published_post_status: str | None = None


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
