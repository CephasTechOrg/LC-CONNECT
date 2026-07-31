from __future__ import annotations

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

ProgramMembershipStatus = Literal['active', 'revoked']


class ProgramMembershipRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    status: ProgramMembershipStatus
    verified_at: datetime | None
    revoked_at: datetime | None
    created_at: datetime
    updated_at: datetime
    program_slug: str
    program_name: str
