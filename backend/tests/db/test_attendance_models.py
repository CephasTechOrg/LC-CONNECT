"""Honors attendance model constraints — Phase 1."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import AttendanceRecord, AttendanceSession, Program, ProgramMembership


async def _honors_program(db) -> Program:
    program = Program(slug='presidential_scholars', name='Presidential Scholars')
    db.add(program)
    await db.commit()
    await db.refresh(program)
    return program


def _session_kwargs(*, program_id, started_by_id, status: str = 'open') -> dict:
    now = datetime.now(UTC)
    return {
        'program_id': program_id,
        'title': 'Honors Class',
        'started_by_id': started_by_id,
        'opened_at': now,
        'present_until': now + timedelta(minutes=3),
        'late_until': now + timedelta(minutes=5),
        'status': status,
    }


async def test_only_one_open_session_per_program(db, factory):
    admin = await factory.user(display_name='Instructor')
    program = await _honors_program(db)

    db.add(AttendanceSession(**_session_kwargs(program_id=program.id, started_by_id=admin.id, status='open')))
    await db.commit()

    db.add(
        AttendanceSession(
            **_session_kwargs(program_id=program.id, started_by_id=admin.id, status='open'),
        )
    )
    with pytest.raises(IntegrityError):
        await db.commit()
    await db.rollback()


async def test_closed_and_open_sessions_allowed_for_same_program(db, factory):
    admin = await factory.user(display_name='Instructor')
    program = await _honors_program(db)

    db.add(AttendanceSession(**_session_kwargs(program_id=program.id, started_by_id=admin.id, status='closed')))
    db.add(AttendanceSession(**_session_kwargs(program_id=program.id, started_by_id=admin.id, status='open')))
    await db.commit()


async def test_attendance_record_unique_per_session_and_student(db, factory):
    admin = await factory.user(display_name='Instructor')
    student = await factory.user(display_name='Scholar')
    program = await _honors_program(db)

    session = AttendanceSession(**_session_kwargs(program_id=program.id, started_by_id=admin.id))
    db.add(session)
    await db.flush()

    now = datetime.now(UTC)
    db.add(
        AttendanceRecord(
            session_id=session.id,
            student_id=student.id,
            status='present',
            verification_method='qr',
            checked_in_at=now,
            original_checked_in_at=now,
        )
    )
    await db.commit()

    db.add(
        AttendanceRecord(
            session_id=session.id,
            student_id=student.id,
            status='late',
            verification_method='qr',
            checked_in_at=now,
            original_checked_in_at=now,
        )
    )
    with pytest.raises(IntegrityError):
        await db.commit()
    await db.rollback()


async def test_program_membership_still_gates_honors_roster(db, factory):
    """Attendance does not add a parallel enrollment table — roster stays on ProgramMembership."""
    student = await factory.user(display_name='Scholar')
    program = await _honors_program(db)

    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()

    rows = (
        await db.execute(
            ProgramMembership.__table__.select().where(
                ProgramMembership.user_id == student.id, ProgramMembership.program_id == program.id
            )
        )
    ).all()
    assert len(rows) == 1
