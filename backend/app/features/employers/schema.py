from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

EmployerOrganizationStatus = Literal['pending', 'approved', 'rejected']


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
