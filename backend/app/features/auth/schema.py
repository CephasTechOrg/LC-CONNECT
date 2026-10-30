from typing import Literal
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field


class BootstrapResponse(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_verified: bool
    policies_accepted: bool
    profile_completed: bool
    auth_user_id: UUID
    first_name: str | None = None
    last_name: str | None = None
    # The profile's current display name, so the app can greet the user by name on its first
    # frame instead of waiting on a second request for the profile.
    display_name: str | None = None


class CurrentUserResponse(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_verified: bool
    policies_accepted: bool
    profile_completed: bool = False
    auth_user_id: UUID | None = None
    first_name: str | None = None
    last_name: str | None = None
    # The profile's current display name, so the app can greet the user by name on its first
    # frame instead of waiting on a second request for the profile.
    display_name: str | None = None


class MessageResponse(BaseModel):
    message: str = Field(min_length=1)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr
    # Which portal's /reset-password page to redirect through — the client says which app it is
    # rather than passing an arbitrary URL, so this can never become an open-redirect vector.
    portal: Literal['admin', 'employer']
