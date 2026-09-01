"""Pydantic models for Honors attendance."""

from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field, field_validator


class HonorsAttendanceFeatureStatus(BaseModel):
    enabled: bool


class AttendanceSessionRead(BaseModel):
    id: UUID
    program_id: UUID
    title: str
    started_by_id: UUID
    opened_at: datetime
    present_until: datetime
    late_until: datetime | None
    closed_at: datetime | None
    status: str
    created_at: datetime

    model_config = {'from_attributes': True}


class ActiveAttendanceStudentRead(BaseModel):
    open: bool
    session: AttendanceSessionRead | None = None
    student_status: str | None = None
    checked_in_at: datetime | None = None


class AttendanceCheckInRequest(BaseModel):
    challenge_id: UUID
    expires_at: str = Field(min_length=10, max_length=40)
    token: str = Field(min_length=16, max_length=128)

    @field_validator('token', 'expires_at', mode='before')
    @classmethod
    def _strip_strings(cls, value: str) -> str:
        if isinstance(value, str):
            return value.strip()
        return value


class AttendanceCheckInResponse(BaseModel):
    status: str
    checked_in_at: datetime | None
    session_id: UUID
    message: str
    already_checked_in: bool = False


class StartAttendanceSessionRequest(BaseModel):
    title: str = Field(default='Honors Class', min_length=1, max_length=160)
    present_window_seconds: int | None = Field(default=None, ge=30, le=3600)
    late_window_seconds: int | None = Field(default=None, ge=0, le=3600)


class AttendanceQRPayloadRead(BaseModel):
    v: int
    session_id: UUID
    challenge_id: UUID
    expires_at: str
    token: str


class AttendanceDashboardRead(BaseModel):
    honors_student_count: int
    active_session: AttendanceSessionRead | None = None
    checked_in_count: int | None = None
    remaining_count: int | None = None


class AttendanceRosterEntryRead(BaseModel):
    record_id: UUID | None = None
    student_id: UUID
    display_name: str | None
    email: str
    status: str | None
    checked_in_at: datetime | None


class AttendanceRosterRead(BaseModel):
    session: AttendanceSessionRead
    session_id: UUID
    checked_in_count: int
    present_count: int
    late_count: int
    absent_count: int = 0
    excused_count: int = 0
    remaining_count: int
    entries: list[AttendanceRosterEntryRead]


class AttendanceHistoryItemRead(BaseModel):
    session: AttendanceSessionRead
    honors_student_count: int
    checked_in_count: int
    present_count: int
    late_count: int
    absent_count: int
    excused_count: int


class ManualAttendanceCorrectionRequest(BaseModel):
    status: str = Field(pattern='^(present|late|absent|excused)$')
    reason: str = Field(min_length=3, max_length=500)

    @field_validator('reason', mode='before')
    @classmethod
    def _strip_reason(cls, value: str) -> str:
        if isinstance(value, str):
            return value.strip()
        return value


class AttendanceRecordRead(BaseModel):
    id: UUID
    session_id: UUID
    student_id: UUID
    status: str
    verification_method: str
    checked_in_at: datetime | None
    manually_modified: bool
    modification_reason: str | None

    model_config = {'from_attributes': True}
