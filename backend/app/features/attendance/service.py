"""Honors attendance business logic — sessions, QR, and check-in."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.config import settings
from app.features.attendance import challenges, qr
from app.models import AttendanceRecord, AttendanceSession, Profile, ProgramMembership, User
from app.models.attendance import ATTENDANCE_SESSION_OPEN_STATUS
from app.shared.programs import PRESIDENTIAL_SCHOLARS_SLUG

SESSION_CLOSED = 'closed'
RECORD_PRESENT = 'present'
RECORD_LATE = 'late'
RECORD_ABSENT = 'absent'
RECORD_EXCUSED = 'excused'
VERIFICATION_QR = 'qr'
VERIFICATION_MANUAL = 'manual'
RECORD_CHECKED_IN = frozenset({RECORD_PRESENT, RECORD_LATE})
RECORD_STATUSES = frozenset({RECORD_PRESENT, RECORD_LATE, RECORD_ABSENT, RECORD_EXCUSED})

_PRESENT_WINDOW_MIN = 30
_PRESENT_WINDOW_MAX = 3600
_LATE_WINDOW_MAX = 3600
_TITLE_MAX = 160


def _now() -> datetime:
    return datetime.now(UTC)


def _ensure_signing_configured() -> None:
    if not qr.signing_secret_configured():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Honors attendance is not configured (missing QR signing secret)',
        )


def _session_close_at(session: AttendanceSession) -> datetime:
    return session.late_until or session.present_until


async def get_honors_program_id(db: AsyncSession) -> UUID | None:
    from app.models import Program

    return (
        await db.execute(
            select(Program.id).where(Program.slug == PRESIDENTIAL_SCHOLARS_SLUG, Program.is_active.is_(True))
        )
    ).scalar_one_or_none()


async def count_active_honors_students(db: AsyncSession, program_id: UUID) -> int:
    return (
        await db.execute(
            select(func.count())
            .select_from(ProgramMembership)
            .where(ProgramMembership.program_id == program_id, ProgramMembership.status == 'active')
        )
    ).scalar_one()


async def get_open_session(db: AsyncSession, *, program_id: UUID) -> AttendanceSession | None:
    return (
        await db.execute(
            select(AttendanceSession).where(
                AttendanceSession.program_id == program_id,
                AttendanceSession.status == ATTENDANCE_SESSION_OPEN_STATUS,
            )
        )
    ).scalar_one_or_none()


async def get_session_or_404(db: AsyncSession, session_id: UUID) -> AttendanceSession:
    session = await db.get(AttendanceSession, session_id)
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Attendance session not found')
    return session


async def maybe_auto_close_session(db: AsyncSession, session: AttendanceSession) -> AttendanceSession:
    if session.status != ATTENDANCE_SESSION_OPEN_STATUS:
        return session
    if _now() <= _session_close_at(session):
        return session
    return await close_session(db, session=session)


async def start_session(
    db: AsyncSession,
    *,
    actor_id: UUID,
    title: str,
    present_window_seconds: int | None = None,
    late_window_seconds: int | None = None,
) -> AttendanceSession:
    _ensure_signing_configured()

    cleaned_title = title.strip()
    if not cleaned_title:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Title is required')
    if len(cleaned_title) > _TITLE_MAX:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Title is too long')

    present_seconds = present_window_seconds or settings.attendance_present_window_seconds
    late_seconds = late_window_seconds if late_window_seconds is not None else settings.attendance_late_window_seconds
    if present_seconds < _PRESENT_WINDOW_MIN or present_seconds > _PRESENT_WINDOW_MAX:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Invalid present window')
    if late_seconds < 0 or late_seconds > _LATE_WINDOW_MAX:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Invalid late window')

    program_id = await get_honors_program_id(db)
    if program_id is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Honors program is not configured',
        )

    existing = await get_open_session(db, program_id=program_id)
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='An attendance session is already open',
        )

    opened = _now()
    session = AttendanceSession(
        program_id=program_id,
        title=cleaned_title,
        started_by_id=actor_id,
        opened_at=opened,
        present_until=opened + timedelta(seconds=present_seconds),
        late_until=opened + timedelta(seconds=present_seconds + late_seconds) if late_seconds > 0 else None,
        status=ATTENDANCE_SESSION_OPEN_STATUS,
    )
    db.add(session)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='An attendance session is already open',
        ) from exc
    await db.refresh(session)
    return session


async def close_session(db: AsyncSession, *, session: AttendanceSession) -> AttendanceSession:
    if session.status == SESSION_CLOSED:
        return session

    now = _now()
    session.status = SESSION_CLOSED
    session.closed_at = now

    member_ids = (
        await db.execute(
            select(ProgramMembership.user_id).where(
                ProgramMembership.program_id == session.program_id,
                ProgramMembership.status == 'active',
            )
        )
    ).scalars().all()

    existing_student_ids = set(
        (
            await db.execute(
                select(AttendanceRecord.student_id).where(AttendanceRecord.session_id == session.id)
            )
        ).scalars().all()
    )

    for student_id in member_ids:
        if student_id in existing_student_ids:
            continue
        db.add(
            AttendanceRecord(
                session_id=session.id,
                student_id=student_id,
                status=RECORD_ABSENT,
                verification_method=VERIFICATION_QR,
            )
        )

    await db.commit()
    await db.refresh(session)
    await challenges.clear_session_challenges(session.id)
    return session


async def close_session_by_id(db: AsyncSession, *, session_id: UUID) -> AttendanceSession:
    session = await get_session_or_404(db, session_id)
    session = await maybe_auto_close_session(db, session)
    if session.status == SESSION_CLOSED:
        return session
    return await close_session(db, session=session)


async def issue_qr_challenge(db: AsyncSession, *, session_id: UUID) -> qr.QRChallenge:
    session = await get_session_or_404(db, session_id)
    session = await maybe_auto_close_session(db, session)
    if session.status != ATTENDANCE_SESSION_OPEN_STATUS:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Attendance is closed')

    challenge = qr.build_challenge(session_id)
    await challenges.store_challenge(
        session_id=session_id,
        challenge_id=challenge.challenge_id,
        ttl_seconds=settings.attendance_qr_ttl_seconds,
    )
    return challenge


def _check_in_status(session: AttendanceSession, *, now: datetime) -> str:
    if now <= session.present_until:
        return RECORD_PRESENT
    if session.late_until is not None and now <= session.late_until:
        return RECORD_LATE
    raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Attendance is closed')


async def _existing_record(
    db: AsyncSession, *, session_id: UUID, student_id: UUID
) -> AttendanceRecord | None:
    return (
        await db.execute(
            select(AttendanceRecord).where(
                AttendanceRecord.session_id == session_id,
                AttendanceRecord.student_id == student_id,
            )
        )
    ).scalar_one_or_none()


async def check_in(
    db: AsyncSession,
    *,
    student_id: UUID,
    session_id: UUID,
    challenge_id: UUID,
    expires_at_raw: str,
    token: str,
) -> tuple[AttendanceRecord, bool]:
    try:
        expires_at = qr.parse_expires_at(expires_at_raw)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Invalid QR payload') from exc

    if not qr.challenge_not_expired(expires_at):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail='QR expired. Scan the current classroom code.',
        )

    if not qr.verify_challenge_token(
        session_id=session_id, challenge_id=challenge_id, expires_at=expires_at, token=token
    ):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid QR code')

    if not await challenges.challenge_exists(session_id=session_id, challenge_id=challenge_id):
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail='QR expired. Scan the current classroom code.',
        )

    session = await get_session_or_404(db, session_id)
    session = await maybe_auto_close_session(db, session)
    if session.status != ATTENDANCE_SESSION_OPEN_STATUS:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Attendance is closed')

    existing = await _existing_record(db, session_id=session_id, student_id=student_id)
    if existing is not None and existing.status in {RECORD_PRESENT, RECORD_LATE}:
        return existing, False

    now = _now()
    record_status = _check_in_status(session, now=now)

    stmt = (
        pg_insert(AttendanceRecord)
        .values(
            session_id=session_id,
            student_id=student_id,
            status=record_status,
            verification_method=VERIFICATION_QR,
            checked_in_at=now,
            original_checked_in_at=now,
        )
        .on_conflict_do_nothing(index_elements=['session_id', 'student_id'])
        .returning(AttendanceRecord.id)
    )
    inserted_id = (await db.execute(stmt)).scalar_one_or_none()
    if inserted_id is None:
        await db.rollback()
        existing = await _existing_record(db, session_id=session_id, student_id=student_id)
        if existing is None:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Check-in failed')
        if existing.status not in RECORD_CHECKED_IN:
            # A concurrent close materialized an absent (or a manual excused) row for this
            # student the instant this scan landed. Report it honestly as closed rather than
            # claiming a check-in that never happened.
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Attendance is closed')
        return existing, False

    await db.commit()
    record = await db.get(AttendanceRecord, inserted_id)
    assert record is not None
    return record, True


async def get_student_record(
    db: AsyncSession, *, session_id: UUID, student_id: UUID
) -> AttendanceRecord | None:
    return await _existing_record(db, session_id=session_id, student_id=student_id)


async def get_active_for_student(
    db: AsyncSession, *, student_id: UUID
) -> tuple[AttendanceSession | None, AttendanceRecord | None]:
    program_id = await get_honors_program_id(db)
    if program_id is None:
        return None, None

    session = await get_open_session(db, program_id=program_id)
    if session is None:
        return None, None

    session = await maybe_auto_close_session(db, session)
    if session.status != ATTENDANCE_SESSION_OPEN_STATUS:
        return None, None

    record = await _existing_record(db, session_id=session.id, student_id=student_id)
    return session, record


async def build_dashboard(db: AsyncSession) -> dict:
    program_id = await get_honors_program_id(db)
    if program_id is None:
        return {'active_session': None, 'honors_student_count': 0}

    honors_count = await count_active_honors_students(db, program_id)
    session = await get_open_session(db, program_id=program_id)
    if session is not None:
        session = await maybe_auto_close_session(db, session)
        if session.status != ATTENDANCE_SESSION_OPEN_STATUS:
            session = None

    active_payload = None
    if session is not None:
        checked_in = (
            await db.execute(
                select(func.count())
                .select_from(AttendanceRecord)
                .where(
                    AttendanceRecord.session_id == session.id,
                    AttendanceRecord.status.in_([RECORD_PRESENT, RECORD_LATE]),
                )
            )
        ).scalar_one()
        active_payload = {
            'session': session,
            'checked_in_count': checked_in,
            'honors_student_count': honors_count,
        }

    return {'active_session': active_payload, 'honors_student_count': honors_count}


async def build_roster(db: AsyncSession, *, session_id: UUID) -> list[tuple[User, Profile | None, AttendanceRecord | None]]:
    session = await get_session_or_404(db, session_id)
    record = aliased(AttendanceRecord)
    rows = (
        await db.execute(
            select(User, Profile, record)
            .join(ProgramMembership, ProgramMembership.user_id == User.id)
            .outerjoin(Profile, Profile.user_id == User.id)
            .outerjoin(
                record,
                (record.session_id == session.id) & (record.student_id == User.id),
            )
            .where(
                ProgramMembership.program_id == session.program_id,
                ProgramMembership.status == 'active',
            )
            .order_by(Profile.display_name.asc().nulls_last(), User.email.asc())
        )
    ).all()
    return list(rows)


async def build_roster_payload(db: AsyncSession, *, session_id: UUID) -> dict:
    session = await get_session_or_404(db, session_id)
    rows = await build_roster(db, session_id=session_id)
    honors_total = len(rows)

    entries: list[dict] = []
    for user, profile, record in rows:
        status_value = None
        checked_in_at = None
        record_id = None
        if record is not None:
            record_id = record.id
            if record.status in RECORD_CHECKED_IN:
                status_value = record.status
                checked_in_at = record.checked_in_at
            elif record.status in {RECORD_ABSENT, RECORD_EXCUSED}:
                status_value = record.status

        entries.append(
            {
                'record_id': record_id,
                'student_id': user.id,
                'display_name': profile.display_name if profile else None,
                'email': user.email,
                'status': status_value,
                'checked_in_at': checked_in_at,
            }
        )

    counts = await _record_status_counts(db, session_id=session.id)
    return {
        'session': session,
        'session_id': session.id,
        'checked_in_count': counts['checked_in'],
        'present_count': counts['present'],
        'late_count': counts['late'],
        'absent_count': counts['absent'],
        'excused_count': counts['excused'],
        'remaining_count': max(0, honors_total - counts['checked_in']),
        'entries': entries,
    }


async def _record_status_counts(db: AsyncSession, *, session_id: UUID) -> dict[str, int]:
    rows = (
        await db.execute(
            select(AttendanceRecord.status, func.count())
            .where(AttendanceRecord.session_id == session_id)
            .group_by(AttendanceRecord.status)
        )
    ).all()
    counts = {record_status: 0 for record_status in RECORD_STATUSES}
    for record_status, count in rows:
        counts[record_status] = count
    checked_in = counts[RECORD_PRESENT] + counts[RECORD_LATE]
    return {
        'present': counts[RECORD_PRESENT],
        'late': counts[RECORD_LATE],
        'absent': counts[RECORD_ABSENT],
        'excused': counts[RECORD_EXCUSED],
        'checked_in': checked_in,
    }


async def list_session_history(db: AsyncSession, *, limit: int = 20) -> list[dict]:
    program_id = await get_honors_program_id(db)
    if program_id is None:
        return []

    honors_count = await count_active_honors_students(db, program_id)
    sessions = (
        await db.execute(
            select(AttendanceSession)
            .where(AttendanceSession.program_id == program_id)
            .order_by(AttendanceSession.opened_at.desc())
            .limit(limit)
        )
    ).scalars().all()

    items: list[dict] = []
    for session in sessions:
        counts = await _record_status_counts(db, session_id=session.id)
        items.append(
            {
                'session': session,
                'honors_student_count': honors_count,
                'checked_in_count': counts['checked_in'],
                'present_count': counts['present'],
                'late_count': counts['late'],
                'absent_count': counts['absent'],
                'excused_count': counts['excused'],
            }
        )
    return items


async def manual_correct_record(
    db: AsyncSession,
    *,
    actor_id: UUID,
    record_id: UUID,
    new_status: str,
    reason: str,
) -> AttendanceRecord:
    from app.models import AttendanceAuditLog

    cleaned_reason = reason.strip()
    if new_status not in RECORD_STATUSES:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='Invalid attendance status')
    if len(cleaned_reason) < 3:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail='A reason is required')

    record = await db.get(AttendanceRecord, record_id)
    if record is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Attendance record not found')

    # Validates the record's session exists (404 otherwise); the row itself isn't needed here.
    await get_session_or_404(db, record.session_id)
    previous_status = record.status
    if previous_status == new_status:
        return record

    now = _now()
    db.add(
        AttendanceAuditLog(
            attendance_record_id=record.id,
            changed_by_id=actor_id,
            previous_status=previous_status,
            new_status=new_status,
            reason=cleaned_reason,
        )
    )

    record.status = new_status
    record.manually_modified = True
    record.modified_by_id = actor_id
    record.modified_at = now
    record.modification_reason = cleaned_reason
    record.verification_method = VERIFICATION_MANUAL
    if new_status in RECORD_CHECKED_IN and record.checked_in_at is None:
        record.checked_in_at = now
        record.original_checked_in_at = now

    await db.commit()
    await db.refresh(record)
    return record
