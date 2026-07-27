"""Legacy auth request/response schemas.

These back the transitional `app/routers/auth.py` (password register/login/OTP flow)
that runs alongside the Supabase-auth path during rollout. Everything else has moved
into `app/features/<domain>/schema.py`. This file retires with the legacy auth router.
"""

from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, field_validator

from app.shared.email_roles import normalize_campus_email


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=120)

    @field_validator('email')
    @classmethod
    def must_be_livingstone_email(cls, v: str) -> str:
        return normalize_campus_email(v)


class VerifyEmailRequest(BaseModel):
    otp: str = Field(min_length=6, max_length=6)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    otp: str = Field(min_length=6, max_length=6)
    new_password: str = Field(min_length=8, max_length=128)


class MessageResponse(BaseModel):
    message: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = 'bearer'


class CurrentUserResponse(BaseModel):
    id: UUID
    email: EmailStr
    role: str
    status: str
    is_verified: bool
