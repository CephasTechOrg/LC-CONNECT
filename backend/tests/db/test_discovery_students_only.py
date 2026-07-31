"""Discovery must remain a student-only social surface."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.dependencies import require_verified_connect_student
from app.features.discovery.router import get_discovery_cards
from app.models import Profile


async def test_require_verified_connect_student_blocks_staff():
    staff = type('User', (), {'is_verified': True, 'role': 'staff'})()
    with pytest.raises(HTTPException) as exc:
        await require_verified_connect_student(staff)  # type: ignore[arg-type]
    assert exc.value.status_code == 403


async def test_discovery_excludes_staff_candidates(db, factory):
    student = await factory.user(display_name='Student A')
    student.role = 'student'
    student_profile = (await db.execute(select(Profile).where(Profile.user_id == student.id))).scalar_one()
    student_profile.display_name = 'Student A'
    student_profile.major = 'Biology'
    student_profile.class_year = 2027
    from app.models import LookingForOption

    option = LookingForOption(code='friendship', name='Friendship')
    db.add(option)
    await db.flush()
    student_profile.looking_for_options = [option]
    student_profile.profile_completed = True
    await db.commit()

    staff = await factory.user(display_name='Staff Person')
    staff.role = 'staff'
    staff_profile = (await db.execute(select(Profile).where(Profile.user_id == staff.id))).scalar_one()
    staff_profile.display_name = 'Staff Person'
    staff_profile.major = 'Biology'
    staff_profile.class_year = 2027
    staff_profile.looking_for_options = [option]
    staff_profile.profile_completed = True
    await db.commit()

    viewer = await factory.user(display_name='Viewer')
    viewer.role = 'student'
    await db.commit()

    cards = await get_discovery_cards(current_user=viewer, db=db, limit=20)
    user_ids = {card.user_id for card in cards}
    assert student.id in user_ids
    assert staff.id not in user_ids
    # is_verified rides along on every card (drives the checkmark badge in the app).
    student_card = next(card for card in cards if card.user_id == student.id)
    assert student_card.is_verified is True
