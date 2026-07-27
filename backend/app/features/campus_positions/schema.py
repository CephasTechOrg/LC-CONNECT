from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

CampusCategory = Literal['academic', 'advising', 'residential_life', 'campus_services']
CampusPositionStatus = Literal['pending', 'verified', 'rejected', 'revoked']


class CampusPositionRead(BaseModel):
    id: UUID
    user_id: UUID
    category: CampusCategory
    official_title: str
    department: str
    office_location: str | None
    phone: str | None
    contact_email: EmailStr
    availability: str | None
    bio: str | None
    status: CampusPositionStatus
    is_primary: bool
    verified_at: datetime | None
    created_at: datetime
    updated_at: datetime


class CampusPositionCreate(BaseModel):
    category: CampusCategory
    official_title: str = Field(min_length=1, max_length=160)
    department: str = Field(min_length=1, max_length=160)
    office_location: str | None = Field(default=None, max_length=160)
    phone: str | None = Field(default=None, max_length=40)
    contact_email: EmailStr | None = None
    availability: str | None = Field(default=None, max_length=500)
    bio: str | None = Field(default=None, max_length=500)


class CampusPositionUpdate(BaseModel):
    category: CampusCategory | None = None
    official_title: str | None = Field(default=None, min_length=1, max_length=160)
    department: str | None = Field(default=None, min_length=1, max_length=160)
    office_location: str | None = Field(default=None, max_length=160)
    phone: str | None = Field(default=None, max_length=40)
    contact_email: EmailStr | None = None
    availability: str | None = Field(default=None, max_length=500)
    bio: str | None = Field(default=None, max_length=500)
