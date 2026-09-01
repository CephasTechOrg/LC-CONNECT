"""Honors attendance session-open notifications — Phase 5 (in-app + push fan-out)."""

from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from sqlalchemy import select

from app.config import settings
from app.features.attendance import challenges, notifications, service
from app.features.notifications.push import push_sender
from app.models import DeviceToken, Notification, Program, ProgramMembership


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


async def _honors_student(db, factory, program: Program, *, token: str | None = None):
    student = await factory.user(display_name='Scholar')
    db.add(ProgramMembership(user_id=student.id, program_id=program.id, status='active'))
    if token is not None:
        db.add(DeviceToken(user_id=student.id, token=token, platform='ios'))
    await db.commit()
    return student


async def test_member_device_tokens_only_active_members(db, factory):
    program = await _honors_program(db)
    await _honors_student(db, factory, program, token='tok-member')

    outsider = await factory.user(display_name='Outsider')
    db.add(DeviceToken(user_id=outsider.id, token='tok-outsider', platform='ios'))

    revoked = await factory.user(display_name='Revoked')
    db.add(ProgramMembership(user_id=revoked.id, program_id=program.id, status='revoked'))
    db.add(DeviceToken(user_id=revoked.id, token='tok-revoked', platform='ios'))
    await db.commit()

    tokens = await notifications._member_device_tokens(db, program.id)
    assert tokens == ['tok-member']


async def test_active_member_ids_excludes_revoked(db, factory):
    program = await _honors_program(db)
    member = await _honors_student(db, factory, program)
    revoked = await factory.user(display_name='Revoked')
    db.add(ProgramMembership(user_id=revoked.id, program_id=program.id, status='revoked'))
    await db.commit()

    ids = await notifications._active_member_ids(db, program.id)
    assert ids == [member.id]


async def test_notify_session_open_fans_out(db, factory, sessions, monkeypatch):
    program = await _honors_program(db)
    student_a = await _honors_student(db, factory, program, token='tok-a')
    student_b = await _honors_student(db, factory, program)  # no device token
    outsider = await factory.user(display_name='Outsider')
    db.add(DeviceToken(user_id=outsider.id, token='tok-outsider', platform='ios'))
    await db.commit()

    instructor = await factory.user(display_name='Instructor')
    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')

    # The fan-out opens its own session — point it at the test database.
    monkeypatch.setattr(notifications, 'AsyncSessionLocal', sessions)

    pushed: dict = {}

    async def fake_push(_db, *, tokens, session_id):
        pushed['tokens'] = tokens
        pushed['session_id'] = session_id

    monkeypatch.setattr(push_sender, 'notify_honors_attendance_open', fake_push)

    published: list = []
    import app.features.realtime.runtime as runtime

    async def fake_publish(user_id, frame):
        published.append((user_id, frame))

    monkeypatch.setattr(runtime.event_bus, 'publish_to_user', fake_publish)

    await notifications.notify_attendance_session_open(session.id)

    rows = (
        await db.execute(
            select(Notification).where(Notification.type == 'honors_attendance_open')
        )
    ).scalars().all()
    recipient_ids = {row.user_id for row in rows}
    assert recipient_ids == {student_a.id, student_b.id}

    assert pushed['tokens'] == ['tok-a']
    assert pushed['session_id'] == session.id

    assert {user_id for user_id, _ in published} == {student_a.id, student_b.id}
    assert all(frame['type'] == 'notification' for _, frame in published)


async def test_notify_session_open_noop_without_members(db, factory, sessions, monkeypatch):
    await _honors_program(db)
    instructor = await factory.user(display_name='Instructor')
    session = await service.start_session(db, actor_id=instructor.id, title='Honors Class')

    monkeypatch.setattr(notifications, 'AsyncSessionLocal', sessions)
    push_mock = AsyncMock()
    monkeypatch.setattr(push_sender, 'notify_honors_attendance_open', push_mock)

    await notifications.notify_attendance_session_open(session.id)

    rows = (
        await db.execute(
            select(Notification).where(Notification.type == 'honors_attendance_open')
        )
    ).scalars().all()
    assert rows == []
    push_mock.assert_not_called()
