from __future__ import annotations

import re
from datetime import datetime
from typing import Literal
from urllib.parse import urlsplit
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

ScholarReviewStatus = Literal[
    'draft',
    'pending_review',
    'approved',
    'changes_requested',
    'revoked',
]


def _strip_or_none(value: object) -> object:
    if isinstance(value, str):
        cleaned = value.strip()
        return cleaned or None
    return value


_SCHEME = re.compile(r'^[a-z][a-z0-9+.\-]*:')


def _http_url_or_none(value: object) -> object:
    """Allow clearing via empty/whitespace; otherwise an http(s) URL — never javascript:/data:.

    A bare `linkedin.com/in/me` gets `https://` added rather than being rejected: rejecting it
    failed the student's whole profile save (summary, skills and all) over one link, and the app's
    own hint invited typing it that way. Anything with another scheme is still refused.
    """
    cleaned = _strip_or_none(value)
    if cleaned is None:
        return None
    if not isinstance(cleaned, str):
        return cleaned
    if not _SCHEME.match(cleaned.lower()):
        cleaned = f'https://{cleaned}'
    parsed = urlsplit(cleaned)
    if parsed.scheme.lower() not in ('http', 'https'):
        raise ValueError('URL must start with http:// or https://')
    if '.' not in parsed.netloc or any(ch.isspace() for ch in cleaned):
        raise ValueError('Enter a web address like linkedin.com/in/your-name')
    return cleaned


class ScholarInternshipEntry(BaseModel):
    """One past or current internship / work experience line."""

    title: str = Field(..., min_length=1, max_length=120)
    organization: str = Field(..., min_length=1, max_length=160)
    start_date: str | None = Field(default=None, max_length=40)
    end_date: str | None = Field(default=None, max_length=40)
    is_current: bool = False
    description: str | None = Field(default=None, max_length=500)

    @field_validator('title', 'organization', mode='before')
    @classmethod
    def _strip_required(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip()
        return value

    @field_validator('start_date', 'end_date', 'description', mode='before')
    @classmethod
    def _strip_optional(cls, value: object) -> object:
        return _strip_or_none(value)

    @model_validator(mode='after')
    def _current_clears_end(self) -> ScholarInternshipEntry:
        if self.is_current and self.end_date is not None:
            return self.model_copy(update={'end_date': None})
        return self


class ScholarProjectEntry(BaseModel):
    """One project the scholar wants employers to see."""

    name: str = Field(..., min_length=1, max_length=160)
    role: str | None = Field(default=None, max_length=120)
    url: str | None = Field(default=None, max_length=300)
    description: str | None = Field(default=None, max_length=500)

    @field_validator('name', mode='before')
    @classmethod
    def _strip_name(cls, value: object) -> object:
        if isinstance(value, str):
            return value.strip()
        return value

    @field_validator('role', 'description', mode='before')
    @classmethod
    def _strip_optional(cls, value: object) -> object:
        return _strip_or_none(value)

    @field_validator('url', mode='before')
    @classmethod
    def _http_url(cls, value: object) -> object:
        return _http_url_or_none(value)


class ScholarProfessionalProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    linkedin_url: str | None
    handshake_url: str | None
    summary: str | None
    skills: list[str]
    career_interests: list[str]
    internships: list[ScholarInternshipEntry]
    projects: list[ScholarProjectEntry]
    employer_visibility_consent: bool
    consent_given_at: datetime | None
    review_status: ScholarReviewStatus
    review_note: str | None
    submitted_at: datetime | None
    reviewed_at: datetime | None
    has_headshot: bool
    has_resume: bool
    created_at: datetime
    updated_at: datetime
    # Server-owned, so mobile / admin / employer views cannot each derive a different answer.
    # Drives whether the dashboard prompt retires; `missing_fields` lets the prompt say what is
    # still outstanding. See `service.missing_profile_fields`.
    is_complete: bool
    missing_fields: list[str]


class ScholarProfessionalProfileUpdate(BaseModel):
    linkedin_url: str | None = Field(default=None, max_length=300)
    handshake_url: str | None = Field(default=None, max_length=300)
    summary: str | None = Field(default=None, max_length=2000)
    skills: list[str] | None = Field(default=None, max_length=30)
    career_interests: list[str] | None = Field(default=None, max_length=30)
    internships: list[ScholarInternshipEntry] | None = Field(default=None, max_length=5)
    projects: list[ScholarProjectEntry] | None = Field(default=None, max_length=5)

    @field_validator('linkedin_url', 'handshake_url', mode='before')
    @classmethod
    def _http_urls(cls, value: object) -> object:
        return _http_url_or_none(value)


class ConsentUpdateRequest(BaseModel):
    consent: bool


class SignedUrlRead(BaseModel):
    url: str
    expires_in: int
