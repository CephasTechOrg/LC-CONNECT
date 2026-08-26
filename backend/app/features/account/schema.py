from __future__ import annotations

from pydantic import BaseModel, EmailStr, Field


class AccountDeleteRequest(BaseModel):
    """Self-service account deletion.

    - ``confirm_email`` must equal the caller's email (anti-misclick).
    - ``password`` is a step-up reauthentication — a stolen bearer token alone cannot delete.
    """

    confirm_email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class AccountDeleteResponse(BaseModel):
    status: str = 'deleted'
