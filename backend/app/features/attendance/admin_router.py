"""Honors attendance — admin portal routes (`honors_admin` scope)."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.features.attendance import service
from app.features.attendance.notifications import notify_attendance_session_open
from app.features.attendance.permissions import require_honors_attendance_admin
from app.features.attendance.schema import (
    AttendanceDashboardRead,
    AttendanceHistoryItemRead,
    AttendanceQRPayloadRead,
    AttendanceRecordRead,
    AttendanceRosterEntryRead,
    AttendanceRosterRead,
    AttendanceSessionRead,
    ManualAttendanceCorrectionRequest,
    StartAttendanceSessionRequest,
)
from app.models import User

router = APIRouter(prefix='/attendance', tags=['admin-attendance'])


@router.get('/honors', response_model=AttendanceDashboardRead)
async def honors_attendance_dashboard(
    _: User = Depends(require_honors_attendance_admin),
    db: AsyncSession = Depends(get_db),
) -> AttendanceDashboardRead:
    data = await service.build_dashboard(db)
    active = data['active_session']
    if active is None:
        return AttendanceDashboardRead(honors_student_count=data['honors_student_count'])

    session = active['session']
    checked_in = active['checked_in_count']
    total = active['honors_student_count']
    return AttendanceDashboardRead(
        honors_student_count=total,
        active_session=AttendanceSessionRead.model_validate(session),
        checked_in_count=checked_in,
        remaining_count=max(0, total - checked_in),
    )


@router.get('/honors/history', response_model=list[AttendanceHistoryItemRead])
async def honors_attendance_history(
    _: User = Depends(require_honors_attendance_admin),
    db: AsyncSession = Depends(get_db),
) -> list[AttendanceHistoryItemRead]:
    items = await service.list_session_history(db)
    return [
        AttendanceHistoryItemRead(
            session=AttendanceSessionRead.model_validate(item['session']),
            honors_student_count=item['honors_student_count'],
            checked_in_count=item['checked_in_count'],
            present_count=item['present_count'],
            late_count=item['late_count'],
            absent_count=item['absent_count'],
            excused_count=item['excused_count'],
        )
        for item in items
    ]


@router.post('/honors/sessions', response_model=AttendanceSessionRead, status_code=201)
async def start_honors_attendance_session(
    payload: StartAttendanceSessionRequest,
    background_tasks: BackgroundTasks,
    actor: User = Depends(require_honors_attendance_admin),
    db: AsyncSession = Depends(get_db),
) -> AttendanceSessionRead:
    session = await service.start_session(
        db,
        actor_id=actor.id,
        title=payload.title,
        present_window_seconds=payload.present_window_seconds,
        late_window_seconds=payload.late_window_seconds,
    )
    # Notify active Honors students after the response — never block starting attendance.
    background_tasks.add_task(notify_attendance_session_open, session.id)
    return AttendanceSessionRead.model_validate(session)


@router.get('/sessions/{session_id}/qr', response_model=AttendanceQRPayloadRead)
async def get_session_qr_challenge(
    session_id: UUID,
    _: User = Depends(require_honors_attendance_admin),
    db: AsyncSession = Depends(get_db),
) -> AttendanceQRPayloadRead:
    challenge = await service.issue_qr_challenge(db, session_id=session_id)
    return AttendanceQRPayloadRead(**challenge.as_payload())


@router.get('/sessions/{session_id}/roster', response_model=AttendanceRosterRead)
async def get_session_roster(
    session_id: UUID,
    _: User = Depends(require_honors_attendance_admin),
    db: AsyncSession = Depends(get_db),
) -> AttendanceRosterRead:
    payload = await service.build_roster_payload(db, session_id=session_id)
    return AttendanceRosterRead(
        session=AttendanceSessionRead.model_validate(payload['session']),
        session_id=payload['session_id'],
        checked_in_count=payload['checked_in_count'],
        present_count=payload['present_count'],
        late_count=payload['late_count'],
        absent_count=payload['absent_count'],
        excused_count=payload['excused_count'],
        remaining_count=payload['remaining_count'],
        entries=[AttendanceRosterEntryRead(**entry) for entry in payload['entries']],
    )


@router.post('/sessions/{session_id}/close', response_model=AttendanceSessionRead)
async def close_attendance_session(
    session_id: UUID,
    _: User = Depends(require_honors_attendance_admin),
    db: AsyncSession = Depends(get_db),
) -> AttendanceSessionRead:
    session = await service.close_session_by_id(db, session_id=session_id)
    return AttendanceSessionRead.model_validate(session)


@router.patch('/records/{record_id}', response_model=AttendanceRecordRead)
async def correct_attendance_record(
    record_id: UUID,
    payload: ManualAttendanceCorrectionRequest,
    actor: User = Depends(require_honors_attendance_admin),
    db: AsyncSession = Depends(get_db),
) -> AttendanceRecordRead:
    record = await service.manual_correct_record(
        db,
        actor_id=actor.id,
        record_id=record_id,
        new_status=payload.status,
        reason=payload.reason,
    )
    return AttendanceRecordRead.model_validate(record)
