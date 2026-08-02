from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, HttpUrl, field_validator

from app.features.campus_hub.schema import OPPORTUNITY_CATEGORIES

EmployerOrganizationStatus = Literal['pending', 'approved', 'rejected']
OpportunitySubmissionStatus = Literal['pending', 'approved', 'rejected']


class EmployerRegisterRequest(BaseModel):
    organization_name: str = Field(min_length=1, max_length=200)
    contact_name: str = Field(min_length=1, max_length=120)
    contact_email: EmailStr


class EmployerOrganizationRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    status: EmployerOrganizationStatus
    created_at: datetime


class OpportunitySubmissionCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1, max_length=8000)
    category: str
    external_url: HttpUrl | None = None

    @field_validator('category')
    @classmethod
    def _valid_category(cls, value: str) -> str:
        if value not in OPPORTUNITY_CATEGORIES:
            allowed = ', '.join(sorted(OPPORTUNITY_CATEGORIES))
            raise ValueError(f'category must be one of: {allowed}')
        return value


class OpportunitySubmissionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    description: str
    category: str
    external_url: str | None
    status: OpportunitySubmissionStatus
    review_note: str | None
    created_at: datetime


class MyEmployerRead(BaseModel):
    """The employer portal's session-check payload — mirrors the admin portal's `bootstrapUser`,
    but resolved against `EmployerAccount`/`EmployerOrganization`, not `User`."""

    organization_id: UUID
    organization_name: str
    organization_status: EmployerOrganizationStatus
    email: EmailStr
    display_name: str | None


class EmployerScholarView(BaseModel):
    """The **entire** employer-facing view of a scholar — deliberately hand-built (never
    `ProfilePublic.model_validate(...)`, never `**profile.__dict__`) so a future field added to
    the social `Profile` or `User` can never leak through here by accident. `display_name` is the
    one non-"professional" field allowed — baseline identification, not social/behavioral data
    (no bio, major, class year, interests, avatar, activities, groups, or messages)."""

    user_id: UUID
    display_name: str | None
    linkedin_url: str | None
    handshake_url: str | None
    summary: str | None
    skills: list[str]
    career_interests: list[str]
    has_headshot: bool
    has_resume: bool
    # A short-lived signed URL for the headshot, so the portal can render the face inline instead
    # of making the employer click through to a separate tab. Deliberate, reviewed addition to
    # this allowlist: it exposes nothing an approved employer couldn't already fetch via
    # `GET /employers/scholars/{id}/headshot-url` — it just saves a round trip. Null when there
    # is no headshot, or when signing failed (the card falls back to initials).
    headshot_url: str | None = None
