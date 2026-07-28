from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

CampusCategory = Literal['academic', 'advising', 'residential_life', 'campus_services', 'campus_safety']
CampusPositionStatus = Literal['pending', 'verified', 'rejected', 'revoked']


class CampusPositionRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

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


# Note: no contact_email input. A staff member's contact email is always their account email —
# it's never a separate field to fill in (that was a redundant box). The service sets it.
class CampusPositionCreate(BaseModel):
    category: CampusCategory
    official_title: str = Field(min_length=1, max_length=160)
    department: str = Field(min_length=1, max_length=160)
    office_location: str | None = Field(default=None, max_length=160)
    phone: str | None = Field(default=None, max_length=40)
    availability: str | None = Field(default=None, max_length=500)
    bio: str | None = Field(default=None, max_length=500)


class CampusPositionUpdate(BaseModel):
    category: CampusCategory | None = None
    official_title: str | None = Field(default=None, min_length=1, max_length=160)
    department: str | None = Field(default=None, min_length=1, max_length=160)
    office_location: str | None = Field(default=None, max_length=160)
    phone: str | None = Field(default=None, max_length=40)
    availability: str | None = Field(default=None, max_length=500)
    bio: str | None = Field(default=None, max_length=500)
