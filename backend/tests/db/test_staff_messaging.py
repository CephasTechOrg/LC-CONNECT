"""Staff↔anyone messaging — verified position required, bidirectional, revocable."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.admin.campus_positions import approve_position, revoke_position
from app.features.campus_positions.schema import CampusPositionCreate
from app.features.campus_positions.service import upsert_primary_position
from app.features.messages.service import list_threads_for_user
from app.features.messages.staff_messaging import create_staff_thread, search_recipients
from app.models import Profile
from app.shared.conversations import accessible_conversation
from app.shared.policies import can_message_as_staff


async def _staff_with_position(db, factory, *, verified: bool, name: str = 'Officer Doe'):
    """A staff user holding a primary position — pending, or admin-approved when `verified`."""
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    staff = await factory.user(display_name=name)
    staff.role = 'staff'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == staff.id))).scalar_one()
    position = await upsert_primary_position(
        db,
        staff,
        profile,
        CampusPositionCreate(
            category='campus_safety',
            official_title='Campus Safety Officer',
            department='Campus Security',
            contact_email=staff.email,
        ),
    )
    if verified:
        await approve_position(db, actor=admin, position_id=position.id)
    return admin, staff, position


async def _student(factory, db, name: str = 'Student'):
    student = await factory.user(display_name=name)
    student.role = 'student'
    await db.commit()
    return student


async def test_unverified_staff_cannot_start_a_thread(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=False)
    student = await _student(factory, db)

    assert await can_message_as_staff(db, staff) is False
    with pytest.raises(HTTPException) as exc:
        await create_staff_thread(db, actor=staff, target_user_id=student.id)
    assert exc.value.status_code == 403


async def test_verified_staff_messages_any_student(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    student = await _student(factory, db)

    thread = await create_staff_thread(db, actor=staff, target_user_id=student.id)
    assert thread.kind == 'staff_dm'
    assert thread.match_id is None  # no connection backs a staff thread
    assert thread.partner is not None and thread.partner.user_id == student.id


async def test_starting_the_same_thread_twice_reuses_the_conversation(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    student = await _student(factory, db)

    first = await create_staff_thread(db, actor=staff, target_user_id=student.id)
    second = await create_staff_thread(db, actor=staff, target_user_id=student.id)
    # And from the other side — the pair has exactly one conversation, whoever opens it.
    reverse = await create_staff_thread(db, actor=student, target_user_id=staff.id)

    assert first.conversation_id == second.conversation_id == reverse.conversation_id


async def test_student_sees_the_staff_partners_title_and_department(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    student = await _student(factory, db)
    await create_staff_thread(db, actor=staff, target_user_id=student.id)

    threads = await list_threads_for_user(db, student.id)
    assert len(threads) == 1
    assert threads[0].partner_position_title == 'Campus Safety Officer'
    assert threads[0].partner_department == 'Campus Security'


async def test_student_cannot_start_a_thread_with_another_student(db, factory):
    student_a = await _student(factory, db, 'A')
    student_b = await _student(factory, db, 'B')

    with pytest.raises(HTTPException) as exc:
        await create_staff_thread(db, actor=student_a, target_user_id=student_b.id)
    assert exc.value.status_code == 403


async def test_cannot_message_yourself(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)

    with pytest.raises(HTTPException) as exc:
        await create_staff_thread(db, actor=staff, target_user_id=staff.id)
    assert exc.value.status_code == 400


async def test_block_prevents_starting_a_thread(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    student = await _student(factory, db)
    await factory.block(student, staff)
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await create_staff_thread(db, actor=staff, target_user_id=student.id)
    assert exc.value.status_code == 403


async def test_revoking_the_position_closes_existing_threads(db, factory):
    admin, staff, position = await _staff_with_position(db, factory, verified=True)
    student = await _student(factory, db)
    thread = await create_staff_thread(db, actor=staff, target_user_id=student.id)

    # Open for both sides while the position stands.
    await accessible_conversation(db, thread.conversation_id, staff.id)
    await accessible_conversation(db, thread.conversation_id, student.id)

    await revoke_position(db, actor=admin, position_id=position.id, review_note='No longer employed')

    for user in (staff, student):
        with pytest.raises(HTTPException) as exc:
            await accessible_conversation(db, thread.conversation_id, user.id)
        assert exc.value.status_code == 403
        # ...and the closed thread drops out of the inbox rather than 403-ing on open.
        assert await list_threads_for_user(db, user.id) == []


async def test_staff_messaging_flag_off_disables_the_capability(db, factory, monkeypatch):
    from app.config import settings

    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    student = await _student(factory, db)
    monkeypatch.setattr(settings, 'staff_messaging_enabled', False)

    assert await can_message_as_staff(db, staff) is False
    with pytest.raises(HTTPException) as exc:
        await create_staff_thread(db, actor=staff, target_user_id=student.id)
    assert exc.value.status_code == 403


async def test_search_finds_students_and_excludes_self(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    await _student(factory, db, 'Searchable Student')

    hits = await search_recipients(db, actor=staff, query='searchable')
    assert [hit.display_name for hit in hits] == ['Searchable Student']

    assert await search_recipients(db, actor=staff, query='Officer Doe') == []


async def test_search_matches_staff_by_official_title(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    _, other_staff, _ = await _staff_with_position(db, factory, verified=True, name='Dean Smith')

    hits = await search_recipients(db, actor=staff, query='campus safety officer')
    assert [hit.user_id for hit in hits] == [other_staff.id]


async def test_search_excludes_blocked_users(db, factory):
    _, staff, _ = await _staff_with_position(db, factory, verified=True)
    student = await _student(factory, db, 'Blocked Student')
    await factory.block(student, staff)
    await db.commit()

    assert await search_recipients(db, actor=staff, query='blocked') == []
