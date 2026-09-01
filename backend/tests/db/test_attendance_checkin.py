"""Honors attendance check-in — Phase 2."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.config import settings
from app.features.attendance import challenges, qr, service
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


async def _open_session(db, factory):
    instructor = await factory.user(display_name='Instructor')
    program = await _honors_program(db)
    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')
    return program, session


async def _valid_challenge(db, session_id):
    challenge = await service.issue_qr_challenge(db, session_id=session_id)
    payload = challenge.as_payload()
    return challenge, str(payload['expires_at']), str(payload['token'])


async def test_check_in_marks_present(db, factory):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)
    challenge, expires_at, token = await _valid_challenge(db, session.id)

    record, created = await service.check_in(
        db,
        student_id=student.id,
        session_id=session.id,
        challenge_id=challenge.challenge_id,
        expires_at_raw=expires_at,
        token=token,
    )
    assert created is True
    assert record.status == 'present'
    assert record.checked_in_at is not None


async def test_check_in_marks_late_after_present_window(db, factory):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)

    session.present_until = datetime.now(UTC) - timedelta(seconds=1)
    session.late_until = datetime.now(UTC) + timedelta(minutes=2)
    await db.commit()

    challenge, expires_at, token = await _valid_challenge(db, session.id)
    record, created = await service.check_in(
        db,
        student_id=student.id,
        session_id=session.id,
        challenge_id=challenge.challenge_id,
        expires_at_raw=expires_at,
        token=token,
    )
    assert created is True
    assert record.status == 'late'


async def test_check_in_rejects_expired_qr(db, factory):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)

    expires_at = datetime.now(UTC) - timedelta(seconds=30)
    challenge_id = uuid4()
    token = qr.sign_challenge(
        session_id=session.id, challenge_id=challenge_id, expires_at=expires_at
    )
    await challenges.store_challenge(
        session_id=session.id,
        challenge_id=challenge_id,
        ttl_seconds=settings.attendance_qr_ttl_seconds,
    )

    with pytest.raises(HTTPException) as exc:
        await service.check_in(
            db,
            student_id=student.id,
            session_id=session.id,
            challenge_id=challenge_id,
            expires_at_raw=expires_at.isoformat(),
            token=token,
        )
    assert exc.value.status_code == 410


async def test_check_in_rejects_invalid_signature(db, factory):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)
    challenge, expires_at, _token = await _valid_challenge(db, session.id)

    with pytest.raises(HTTPException) as exc:
        await service.check_in(
            db,
            student_id=student.id,
            session_id=session.id,
            challenge_id=challenge.challenge_id,
            expires_at_raw=expires_at,
            token='0' * 64,
        )
    assert exc.value.status_code == 400


async def test_check_in_idempotent_for_duplicate_scan(db, factory):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)
    challenge, expires_at, token = await _valid_challenge(db, session.id)

    first, created_first = await service.check_in(
        db,
        student_id=student.id,
        session_id=session.id,
        challenge_id=challenge.challenge_id,
        expires_at_raw=expires_at,
        token=token,
    )
    assert created_first is True

    challenge2, expires_at2, token2 = await _valid_challenge(db, session.id)
    second, created_second = await service.check_in(
        db,
        student_id=student.id,
        session_id=session.id,
        challenge_id=challenge2.challenge_id,
        expires_at_raw=expires_at2,
        token=token2,
    )
    assert created_second is False
    assert second.id == first.id


async def test_check_in_rejects_qr_signed_for_another_session(db, factory):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)

    forged_session_id = uuid4()
    challenge = qr.build_challenge(forged_session_id)
    await challenges.store_challenge(
        session_id=forged_session_id,
        challenge_id=challenge.challenge_id,
        ttl_seconds=settings.attendance_qr_ttl_seconds,
    )

    with pytest.raises(HTTPException) as exc:
        await service.check_in(
            db,
            student_id=student.id,
            session_id=session.id,
            challenge_id=challenge.challenge_id,
            expires_at_raw=challenge.expires_at.isoformat(),
            token=challenge.token,
        )
    assert exc.value.status_code == 400


async def test_concurrent_check_ins_keep_single_row(db, factory, sessions):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)
    challenge, expires_at, token = await _valid_challenge(db, session.id)

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

    results = await asyncio.gather(_attempt(), _attempt(), return_exceptions=True)
    successes = [r for r in results if not isinstance(r, Exception)]
    assert len(successes) == 2
    assert successes[0][0].id == successes[1][0].id

    count = (
        await db.execute(
            select(func.count())
            .select_from(AttendanceRecord)
            .where(
                AttendanceRecord.session_id == session.id,
                AttendanceRecord.student_id == student.id,
            )
        )
    ).scalar_one()
    assert count == 1


async def test_check_in_rejects_unknown_challenge(db, factory):
    program, session = await _open_session(db, factory)
    student = await _honors_student(db, factory, program)
    challenge = qr.build_challenge(session.id)

    with pytest.raises(HTTPException) as exc:
        await service.check_in(
            db,
            student_id=student.id,
            session_id=session.id,
            challenge_id=challenge.challenge_id,
            expires_at_raw=challenge.expires_at.isoformat(),
            token=challenge.token,
        )
    assert exc.value.status_code == 410
