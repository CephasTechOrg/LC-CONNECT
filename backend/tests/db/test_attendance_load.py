"""Honors attendance load/concurrency — Phase 7 pilot hardening (§19.5).

Simulates a burst of distinct students checking in at once (the start-of-class rush) and asserts
the invariants the pilot depends on: exactly one row per student, every successful check-in
persisted, and the admin roster count staying accurate.
"""

from __future__ import annotations

import asyncio

import pytest
from sqlalchemy import func, select

from app.config import settings
from app.features.attendance import challenges, service
from app.models import AttendanceRecord, Program, ProgramMembership

STUDENT_COUNT = 60


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


async def test_burst_check_ins_stay_consistent(db, factory, sessions):
    instructor = await factory.user(display_name='Instructor')
    program = await _honors_program(db)

    students = []
    for i in range(STUDENT_COUNT):
        student = await factory.user(display_name=f'Scholar {i}')
        db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
        students.append(student)
    await db.commit()

    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    challenge = await service.issue_qr_challenge(db, session_id=session.id)
    payload = challenge.as_payload()
    expires_at, token = str(payload['expires_at']), str(payload['token'])

    async def _check_in(student_id):
        async with sessions() as isolated:
            return await service.check_in(
                isolated,
                student_id=student_id,
                session_id=session.id,
                challenge_id=challenge.challenge_id,
                expires_at_raw=expires_at,
                token=token,
            )

    results = await asyncio.gather(
        *(_check_in(s.id) for s in students), return_exceptions=True
    )

    failures = [r for r in results if isinstance(r, Exception)]
    assert not failures, f'unexpected check-in failures: {failures[:3]}'
    assert all(created for _record, created in results)

    total = (
        await db.execute(
            select(func.count()).select_from(AttendanceRecord).where(
                AttendanceRecord.session_id == session.id
            )
        )
    ).scalar_one()
    assert total == STUDENT_COUNT

    distinct = (
        await db.execute(
            select(func.count(func.distinct(AttendanceRecord.student_id))).where(
                AttendanceRecord.session_id == session.id
            )
        )
    ).scalar_one()
    assert distinct == STUDENT_COUNT

    roster = await service.build_roster_payload(db, session_id=session.id)
    assert roster['checked_in_count'] == STUDENT_COUNT
    assert roster['present_count'] == STUDENT_COUNT
    assert roster['remaining_count'] == 0


async def test_duplicate_burst_for_one_student_keeps_single_row(db, factory, sessions):
    instructor = await factory.user(display_name='Instructor')
    program = await _honors_program(db)
    student = await factory.user(display_name='Scholar')
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    await db.commit()

    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    challenge = await service.issue_qr_challenge(db, session_id=session.id)
    payload = challenge.as_payload()
    expires_at, token = str(payload['expires_at']), str(payload['token'])

    async def _attempt():
        async with sessions() as isolated:
            return await service.check_in(
                isolated,
                student_id=student.id,
                session_id=session.id,
                challenge_id=challenge.challenge_id,
                expires_at_raw=expires_at,
                token=token,
            )

    results = await asyncio.gather(*(_attempt() for _ in range(10)), return_exceptions=True)
    successes = [r for r in results if not isinstance(r, Exception)]
    assert len(successes) == 10
    record_ids = {record.id for record, _created in successes}
    assert len(record_ids) == 1

    total = (
        await db.execute(
            select(func.count()).select_from(AttendanceRecord).where(
                AttendanceRecord.session_id == session.id,
                AttendanceRecord.student_id == student.id,
            )
        )
    ).scalar_one()
    assert total == 1
