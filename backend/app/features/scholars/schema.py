from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ScholarProfessionalProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    linkedin_url: str | None
    handshake_url: str | None
    summary: str | None
    skills: list[str]
    career_interests: list[str]
    employer_visibility_consent: bool
    consent_given_at: datetime | None
    has_headshot: bool
    has_resume: bool
    created_at: datetime
    updated_at: datetime


class ScholarProfessionalProfileUpdate(BaseModel):
    linkedin_url: str | None = Field(default=None, max_length=300)
    handshake_url: str | None = Field(default=None, max_length=300)
    summary: str | None = Field(default=None, max_length=2000)
    skills: list[str] | None = Field(default=None, max_length=30)
    career_interests: list[str] | None = Field(default=None, max_length=30)


class ConsentUpdateRequest(BaseModel):
    consent: bool


class SignedUrlRead(BaseModel):
    url: str
    expires_in: int
