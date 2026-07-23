from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ReportCreate(BaseModel):
    reported_user_id: UUID | None = None
    activity_id: UUID | None = None
    group_id: UUID | None = None
    message_id: UUID | None = None
    reason: str = Field(min_length=3, max_length=80)
    details: str | None = Field(default=None, max_length=1000)

    @model_validator(mode='after')
    def require_target(self):
        if not any((self.reported_user_id, self.activity_id, self.group_id, self.message_id)):
            raise ValueError('Provide a report target (user, activity, group, or message)')
        return self
