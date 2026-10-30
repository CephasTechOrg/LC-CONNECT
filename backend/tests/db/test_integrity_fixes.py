"""Races and loose ends closed in the integrity pass: each test reproduces the failure that used
to happen (a 500, a duplicate row, a chat that ignored a disconnect) on real Postgres."""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime

import pytest
from fastapi import HTTPException
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.config import settings
from app.features.attendance import challenges
from app.features.attendance import service as attendance
from app.features.groups import service as groups
from app.features.groups.schema import GroupCreate
from app.features.messages.schema import MessageCreate
from app.features.messages.service import unread_summary
from app.models import (
    AttendanceRecord,
    AttendanceSession,
    Conversation,
    ConversationMember,
    Group,
    Notification,
    Program,
    ProgramMembership,
)
from app.shared.conversations import assert_can_post, ensure_staff_dm_conversation


async def _dm(db, factory):
    a, b = await factory.user(), await factory.user()
    match = await factory.match(a, b)
    conversation = (await db.execute(select(Conversation).where(Conversation.match_id == match.id))).scalar_one()
    return a, b, match, conversation


async def test_a_disconnected_dm_stays_readable_but_takes_nothing_new(db, factory):
    _, _, match, conversation = await _dm(db, factory)
    await assert_can_post(db, conversation)  # connected: fine

    match.disconnected_at = datetime.now(UTC)
    await db.commit()
    with pytest.raises(HTTPException) as exc:
        await assert_can_post(db, conversation)
    assert exc.value.status_code == 403


async def test_two_closes_at_once_mark_each_absent_student_exactly_once(db, sessions, factory, monkeypatch):
    monkeypatch.setattr(settings, 'honors_attendance_enabled', True)
    monkeypatch.setattr(settings, 'attendance_qr_signing_secret', 'test-signing-secret')
    challenges.reset_memory_store_for_tests()
    program = Program(slug='presidential_scholars', name='Presidential Scholars')
    db.add(program)
    await db.commit()
    students = [await factory.user() for _ in range(3)]
    for s in students:
        db.add(ProgramMembership(user_id=s.id, program_id=program.id, status='active'))
    await db.commit()
    session = await attendance.start_session(db, actor_id=(await factory.user()).id, title='Honors')
    session_id = session.id

    async def close():
        async with sessions() as s:
            fresh = await s.get(AttendanceSession, session_id)
            await attendance.close_session(s, session=fresh)

    await asyncio.gather(close(), close())  # used to fail one of them with an IntegrityError
    count = (
        await db.execute(select(func.count()).where(AttendanceRecord.session_id == session_id))
    ).scalar_one()
    assert count == len(students)


async def test_a_double_tap_on_join_is_one_membership_not_a_500(db, sessions, factory):
    owner, joiner = await factory.user(), await factory.user()
    group = await groups.create_group(
        db, owner, GroupCreate(name='Chess', category='club', visibility='public', join_policy='open')
    )
    await db.commit()
    group_id, joiner_id = group.id, joiner.id

    async def join():
        async with sessions() as s:
            g = await s.get(Group, group_id)
            user = await s.get(type(joiner), joiner_id)
            try:
                await groups.join_group(s, g, user)
                await s.commit()
                return 'joined'
            except HTTPException as exc:
                return exc.status_code

    results = await asyncio.gather(join(), join())
    assert sorted(map(str, results)) == ['409', 'joined']  # the second sees the first: "Already a member"
    rows = (
        await db.execute(
            select(func.count()).where(
                ConversationMember.conversation_id == group.conversation_id, ConversationMember.user_id == joiner_id
            )
        )
    ).scalar_one()
    assert rows == 1


async def test_a_double_tap_on_message_staff_makes_one_chat(db, sessions, factory):
    staff, student = await factory.user(), await factory.user()
    await db.commit()

    async def start():
        async with sessions() as s:
            conversation = await ensure_staff_dm_conversation(s, staff.id, student.id)
            await s.commit()
            return conversation.id

    first, second = await asyncio.gather(start(), start())
    assert first == second


async def test_only_one_unread_notification_per_subject(db, factory):
    a, b = await factory.user(), await factory.user()
    subject = (await _dm(db, factory))[3].id
    db.add(Notification(user_id=a.id, type='message_reaction', actor_id=b.id, subject_id=subject))
    await db.commit()
    db.add(Notification(user_id=a.id, type='message_reaction', actor_id=b.id, subject_id=subject))
    with pytest.raises(IntegrityError):
        await db.commit()


async def test_deleted_messages_do_not_count_as_unread(db, factory):
    a, b, match, _ = await _dm(db, factory)
    await factory.message(match, b, 'hello')
    gone = await factory.message(match, b, 'oops')
    gone.deleted_at = datetime.now(UTC)
    await db.commit()

    total, _ = await unread_summary(db, a.id)
    assert total == 1


def test_a_message_of_only_spaces_is_refused():
    with pytest.raises(ValidationError):
        MessageCreate(body='   ')
