"""Honors attendance — student-facing HTTP routes."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.features.attendance import service
from app.features.attendance.permissions import (
    honors_attendance_enabled,
    require_honors_check_in_student,
    require_honors_student,
)
from app.features.attendance.schema import (
    ActiveAttendanceStudentRead,
    AttendanceCheckInRequest,
    AttendanceCheckInResponse,
    AttendanceSessionRead,
    HonorsAttendanceFeatureStatus,
)
from app.models import User

router = APIRouter(prefix='/attendance', tags=['attendance'])


@router.get('/honors/status', response_model=HonorsAttendanceFeatureStatus)
async def honors_attendance_status() -> HonorsAttendanceFeatureStatus:
    return HonorsAttendanceFeatureStatus(enabled=honors_attendance_enabled())


@router.get('/honors/active', response_model=ActiveAttendanceStudentRead)
async def get_active_honors_attendance(
    current_user: User = Depends(require_honors_student),
    db: AsyncSession = Depends(get_db),
) -> ActiveAttendanceStudentRead:
    session, record = await service.get_active_for_student(db, student_id=current_user.id)
    if session is None:
        return ActiveAttendanceStudentRead(open=False)

    student_status = None
    checked_in_at = None
    if record is not None and record.status in {service.RECORD_PRESENT, service.RECORD_LATE}:
        student_status = record.status
        checked_in_at = record.checked_in_at

    return ActiveAttendanceStudentRead(
        open=True,
        session=AttendanceSessionRead.model_validate(session),
        student_status=student_status,
        checked_in_at=checked_in_at,
    )


@router.post('/sessions/{session_id}/check-in', response_model=AttendanceCheckInResponse)
async def check_in_to_session(
    session_id: UUID,
    payload: AttendanceCheckInRequest,
    current_user: User = Depends(require_honors_check_in_student),
    db: AsyncSession = Depends(get_db),
) -> AttendanceCheckInResponse:
    existing = await service.get_student_record(db, session_id=session_id, student_id=current_user.id)
    if existing is not None and existing.status in {service.RECORD_PRESENT, service.RECORD_LATE}:
        return AttendanceCheckInResponse(
            status=existing.status,
            checked_in_at=existing.checked_in_at,
            session_id=session_id,
            message="You're already checked in.",
            already_checked_in=True,
        )

    record, created = await service.check_in(
        db,
        student_id=current_user.id,
        session_id=session_id,
        challenge_id=payload.challenge_id,
        expires_at_raw=payload.expires_at,
        token=payload.token,
    )

    if not created:
        return AttendanceCheckInResponse(
            status=record.status,
            checked_in_at=record.checked_in_at,
            session_id=session_id,
            message="You're already checked in.",
            already_checked_in=True,
        )

    message = "You're checked in."
    if record.status == service.RECORD_LATE:
        message = 'Check-in recorded'

    return AttendanceCheckInResponse(
        status=record.status,
        checked_in_at=record.checked_in_at,
        session_id=session_id,
        message=message,
        already_checked_in=False,
    )
