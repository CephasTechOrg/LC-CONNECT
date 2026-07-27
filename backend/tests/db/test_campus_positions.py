"""Campus position endpoints — Campus Hub Phase 2."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.campus_positions.schema import CampusPositionCreate
from app.features.campus_positions.service import get_primary_position, upsert_primary_position
from app.models import LookingForOption, Profile
from app.shared.onboarding import compute_onboarding_completed


async def test_staff_can_create_pending_position(db, factory):
    user = await factory.user(display_name='Prof')
    user.email = 'prof@livingstone.edu'
    user.role = 'staff'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    profile.display_name = 'Dr. Smith'
    await db.commit()

    position = await upsert_primary_position(
        db,
        user,
        profile,
        CampusPositionCreate(
            category='academic',
            official_title='Associate Professor',
            department='Biology',
            office_location='Science Hall 204',
        ),
    )

    assert position.status == 'pending'
    assert position.is_primary is True
    assert position.contact_email == 'prof@livingstone.edu'

    refreshed_profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    assert refreshed_profile.profile_completed is True


async def test_verified_position_cannot_be_edited(db, factory):
    user = await factory.user(display_name='Verified Prof')
    user.role = 'staff'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    profile.display_name = 'Dr. Verified'
    await db.commit()

    position = await upsert_primary_position(
        db,
        user,
        profile,
        CampusPositionCreate(
            category='advising',
            official_title='Academic Advisor',
            department='Student Success',
        ),
    )
    position.status = 'verified'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await upsert_primary_position(
            db,
            user,
            profile,
            CampusPositionCreate(
                category='advising',
                official_title='Changed Title',
                department='Student Success',
            ),
        )
    assert exc.value.status_code == 403


async def test_student_profile_completion_unchanged(db, factory):
    user = await factory.user(display_name='Student')
    user.role = 'student'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    profile.display_name = 'Jordan'
    profile.major = 'Business'
    profile.class_year = 2027
    option = LookingForOption(code='friendship', name='Friendship')
    db.add(option)
    await db.flush()
    profile.looking_for_options = [option]

    assert compute_onboarding_completed(user, profile, None) is True
    position = await get_primary_position(db, user.id)
    assert position is None
