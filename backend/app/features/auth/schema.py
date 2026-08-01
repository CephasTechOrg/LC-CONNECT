from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class BootstrapResponse(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_verified: bool
    profile_completed: bool
    auth_user_id: UUID


class CurrentUserResponse(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_verified: bool
    profile_completed: bool = False
    auth_user_id: UUID | None = None


class MessageResponse(BaseModel):
    message: str = Field(min_length=1)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr
    # Which portal's /reset-password page to redirect through — the client says which app it is
    # rather than passing an arbitrary URL, so this can never become an open-redirect vector.
    portal: Literal['admin', 'employer']
