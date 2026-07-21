from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ReportCreate(BaseModel):
    reported_user_id: UUID | None = None
    activity_id: UUID | None = None
    reason: str = Field(min_length=3, max_length=80)
    details: str | None = Field(default=None, max_length=1000)

    @model_validator(mode='after')
    def require_target(self):
        if not self.reported_user_id and not self.activity_id:
            raise ValueError('Provide reported_user_id or activity_id')
        return self
