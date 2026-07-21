from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


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
