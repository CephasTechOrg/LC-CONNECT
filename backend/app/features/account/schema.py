from __future__ import annotations

from pydantic import BaseModel, EmailStr


class AccountDeleteRequest(BaseModel):
    """Self-service account deletion. `confirm_email` must equal the caller's own email — a
    deliberate, hard-to-fumble confirmation so the destructive action can't fire by accident."""

    confirm_email: EmailStr


class AccountDeleteResponse(BaseModel):
    status: str = 'deleted'
