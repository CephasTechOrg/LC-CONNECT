"""Honors attendance session lifecycle — Phase 2."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.config import settings
from app.features.attendance import challenges, service
from app.models import AttendanceRecord, Program, ProgramMembership


@pytest.fixture(autouse=True)
def _attendance_config(monkeypatch):
    monkeypatch.setattr(settings, 'honors_attendance_enabled', True)
    monkeypatch.setattr(settings, 'attendance_qr_signing_secret', 'test-signing-secret')
    challenges.reset_memory_store_for_tests()


async def _honors_program(db) -> Program:
    program = Program(slug='presidential_scholars', name='Presidential Scholars')
    db.add(program)
    await db.commit()
    await db.refresh(program)
    return program


async def _honors_student(db, factory, program: Program):
    student = await factory.user(display_name='Scholar')
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()
    return student


async def test_start_session_creates_open_session(db, factory):
    instructor = await factory.user(display_name='Instructor')
    await _honors_program(db)

    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    assert session.status == 'open'
    assert session.title == 'Honors Class'
    assert session.late_until is not None


async def test_start_session_rejects_second_open_session(db, factory):
    instructor = await factory.user(display_name='Instructor')
    await _honors_program(db)
    await service.start_session(db, actor_id=instructor.id, title='First')

    with pytest.raises(HTTPException) as exc:
        await service.start_session(db, actor_id=instructor.id, title='Second')
    assert exc.value.status_code == 409


async def test_start_session_requires_signing_secret(db, factory, monkeypatch):
    monkeypatch.setattr(settings, 'attendance_qr_signing_secret', None)
    instructor = await factory.user(display_name='Instructor')
    await _honors_program(db)

    with pytest.raises(HTTPException) as exc:
        await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    assert exc.value.status_code == 503


async def test_close_session_materializes_absent_rows(db, factory):
    instructor = await factory.user(display_name='Instructor')
    program = await _honors_program(db)
    scholar = await _honors_student(db, factory, program)
    other = await _honors_student(db, factory, program)

    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    challenge = await service.issue_qr_challenge(db, session_id=session.id)
    payload = challenge.as_payload()

    await service.check_in(
        db,
        student_id=scholar.id,
        session_id=session.id,
        challenge_id=challenge.challenge_id,
        expires_at_raw=str(payload['expires_at']),
        token=str(payload['token']),
    )

    closed = await service.close_session_by_id(db, session_id=session.id)
    assert closed.status == 'closed'
    assert closed.closed_at is not None

    records = (
        await db.execute(
            AttendanceRecord.__table__.select().where(AttendanceRecord.session_id == session.id)
        )
    ).all()
    statuses = {row.student_id: row.status for row in records}
    assert statuses[scholar.id] in {'present', 'late'}
    assert statuses[other.id] == 'absent'


async def test_maybe_auto_close_after_late_window(db, factory):
    instructor = await factory.user(display_name='Instructor')
    await _honors_program(db)
    session = await service.start_session(
        db,
        actor_id=instructor.id,
        title='Short',
        present_window_seconds=30,
        late_window_seconds=0,
    )
    session.present_until = datetime.now(UTC) - timedelta(seconds=1)
    await db.commit()

    updated = await service.maybe_auto_close_session(db, session)
    assert updated.status == 'closed'
