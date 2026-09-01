"""Admin attendance history and manual corrections — Phase 3."""

from __future__ import annotations

import pytest
from fastapi import HTTPException

from app.config import settings
from app.features.attendance import challenges, service
from app.models import AttendanceAuditLog, AttendanceRecord, Program, ProgramMembership


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


async def test_list_session_history_returns_recent_sessions(db, factory):
    instructor = await factory.user(display_name='Instructor')
    program = await _honors_program(db)

    first = await service.start_session(db, actor_id=instructor.id, title='Day 1')
    await service.close_session_by_id(db, session_id=first.id)
    second = await service.start_session(db, actor_id=instructor.id, title='Day 2')
    await service.close_session_by_id(db, session_id=second.id)

    history = await service.list_session_history(db, limit=10)
    assert len(history) == 2
    assert history[0]['session'].title == 'Day 2'
    assert history[1]['session'].title == 'Day 1'


async def test_manual_correct_record_writes_audit_log(db, factory):
    instructor = await factory.user(display_name='Instructor')
    student = await factory.user(display_name='Scholar')
    program = await _honors_program(db)
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()

    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    await service.close_session_by_id(db, session_id=session.id)

    record = (
        await db.execute(
            AttendanceRecord.__table__.select().where(
                AttendanceRecord.session_id == session.id,
                AttendanceRecord.student_id == student.id,
            )
        )
    ).first()
    assert record is not None
    assert record.status == 'absent'

    updated = await service.manual_correct_record(
        db,
        actor_id=instructor.id,
        record_id=record.id,
        new_status='excused',
        reason='Approved absence',
    )
    assert updated.status == 'excused'
    assert updated.manually_modified is True

    audit = (
        await db.execute(
            AttendanceAuditLog.__table__.select().where(
                AttendanceAuditLog.attendance_record_id == record.id
            )
        )
    ).first()
    assert audit is not None
    assert audit.previous_status == 'absent'
    assert audit.new_status == 'excused'


async def test_manual_correct_record_requires_reason(db, factory):
    instructor = await factory.user(display_name='Instructor')
    student = await factory.user(display_name='Scholar')
    program = await _honors_program(db)
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()

    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    await service.close_session_by_id(db, session_id=session.id)

    record_id = (
        await db.execute(
            AttendanceRecord.__table__.select().where(AttendanceRecord.session_id == session.id)
        )
    ).first().id

    with pytest.raises(HTTPException) as exc:
        await service.manual_correct_record(
            db,
            actor_id=instructor.id,
            record_id=record_id,
            new_status='present',
            reason='  ',
        )
    assert exc.value.status_code == 422
