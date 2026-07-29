from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, HttpUrl, model_validator


class DirectoryEntryRead(BaseModel):
    position_id: UUID
    user_id: UUID
    display_name: str | None
    avatar_url: str | None
    category: str
    official_title: str
    department: str
    office_location: str | None
    phone: str | None
    contact_email: EmailStr
    availability: str | None
    bio: str | None
    verified_at: datetime | None


class StudentDirectoryEntry(BaseModel):
    """A student as seen by a staff member browsing the student directory — enough to recognise
    and reach out, no matching signals. Staff-only surface (mirrors the staff directory)."""

    profile_id: UUID
    user_id: UUID
    display_name: str | None
    avatar_url: str | None
    major: str | None
    class_year: int | None


class CampusPostSummaryRead(BaseModel):
    id: UUID
    kind: str
    title: str
    summary: str | None
    priority: str
    category: str | None
    publish_at: datetime
    expires_at: datetime | None
    external_url: str | None


class CampusPostRead(CampusPostSummaryRead):
    body: str
    audience: str


class AuthorCampusPostRead(BaseModel):
    """Author-facing post including drafts (publish_at may be null)."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
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


class PublishingCapabilitiesRead(BaseModel):
    can_publish: bool
    staff_publishing_enabled: bool
    reason: str | None = None


class CampusHubOverviewRead(BaseModel):
    urgent_posts: list[CampusPostSummaryRead]
    latest_updates: list[CampusPostSummaryRead]


class CampusResourceRead(BaseModel):
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


class CampusPostCreate(BaseModel):
    # Two clear types students see. Urgency is the `priority` field (urgent → alert banner),
    # not a separate kind — that keeps type and urgency from overlapping.
    kind: str = Field(pattern=r'^(announcement|opportunity)$')
    title: str = Field(min_length=1, max_length=200)
    summary: str | None = Field(default=None, max_length=400)
    body: str = Field(min_length=1, max_length=8000)
    audience: str = Field(default='all', pattern=r'^(all|students|staff)$')
    category: str | None = Field(default=None, max_length=30)
    priority: str = Field(default='normal', pattern=r'^(normal|important|urgent)$')
    publish_at: datetime | None = None
    expires_at: datetime | None = None
    external_url: HttpUrl | None = None

    @model_validator(mode='after')
    def _validate_schedule(self) -> CampusPostCreate:
        if self.expires_at is not None and self.publish_at is not None and self.expires_at <= self.publish_at:
            raise ValueError('expires_at must be after publish_at')
        return self


class CampusPostUpdate(BaseModel):
    kind: str | None = Field(default=None, pattern=r'^(announcement|opportunity)$')
    title: str | None = Field(default=None, min_length=1, max_length=200)
    summary: str | None = Field(default=None, max_length=400)
    body: str | None = Field(default=None, min_length=1, max_length=8000)
    audience: str | None = Field(default=None, pattern=r'^(all|students|staff)$')
    category: str | None = Field(default=None, max_length=30)
    priority: str | None = Field(default=None, pattern=r'^(normal|important|urgent)$')
    publish_at: datetime | None = None
    expires_at: datetime | None = None
    external_url: HttpUrl | None = None

    @model_validator(mode='after')
    def _validate_schedule(self) -> CampusPostUpdate:
        if self.expires_at is not None and self.publish_at is not None and self.expires_at <= self.publish_at:
            raise ValueError('expires_at must be after publish_at')
        return self


class CampusResourceCreate(BaseModel):
    category: str = Field(min_length=1, max_length=30)
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1)
    location: str | None = Field(default=None, max_length=200)
    hours: str | None = Field(default=None, max_length=200)
    contact_email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=40)
    external_url: HttpUrl | None = None
    sort_order: int = 0
    is_active: bool = True


class CampusResourceUpdate(BaseModel):
    category: str | None = Field(default=None, min_length=1, max_length=30)
    title: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, min_length=1)
    location: str | None = Field(default=None, max_length=200)
    hours: str | None = Field(default=None, max_length=200)
    contact_email: EmailStr | None = None
    phone: str | None = Field(default=None, max_length=40)
    external_url: HttpUrl | None = None
    sort_order: int | None = None
    is_active: bool | None = None
