from __future__ import annotations

from typing import Any
from datetime import datetime
from uuid import UUID

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


class SuspensionAppealRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    status: str
    message: str
    admin_note: str | None = None
    created_at: datetime
    reviewed_at: datetime | None = None


class SuspensionStatusResponse(BaseModel):
    is_suspended: bool = True
    support_email: str
    open_appeal: SuspensionAppealRead | None = None


class SuspensionAppealCreate(BaseModel):
    message: str = Field(min_length=10, max_length=2000)


class SuspensionAppealSubmitResponse(BaseModel):
    appeal: SuspensionAppealRead
