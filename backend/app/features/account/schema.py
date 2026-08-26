from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class AccountDeleteRequest(BaseModel):
    """Self-service account deletion.

    - ``confirm_email`` must equal the caller's email (anti-misclick).
    - ``password`` is a step-up reauthentication — a stolen bearer token alone cannot delete.
    """

    confirm_email: EmailStr
    password: str = Field(min_length=1, max_length=128)


class AccountDeleteResponse(BaseModel):
    status: str = 'deleted'


class AccountExportResponse(BaseModel):
    """Machine-readable copy of the caller's own data (privacy right of access).

    Top-level shape is stable; nested sections may grow. Clients should key off
    ``schema_version``. Secrets (password hashes, OTPs, raw push tokens) are never included.
    """

    model_config = ConfigDict(extra='allow')

    exported_at: str
    schema_version: int = 1
    account: dict[str, Any]
    profile: dict[str, Any] | None = None
