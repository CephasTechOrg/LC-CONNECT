"""Hardening: social authz, contact email, and position resubmit lifecycle."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.dependencies import require_verified_connect_student
from app.features.admin.campus_positions import approve_position, revoke_position
from app.features.campus_positions.schema import CampusPositionCreate
from app.features.campus_positions.service import upsert_primary_position
from app.models import Profile
from app.shared.email_roles import normalize_campus_contact_email


async def test_staff_blocked_from_social_guard():
    staff = type('User', (), {'is_verified': True, 'role': 'staff'})()
    with pytest.raises(HTTPException) as exc:
        await require_verified_connect_student(staff)  # type: ignore[arg-type]
    assert exc.value.status_code == 403
    assert 'student' in exc.value.detail.lower()


async def test_student_passes_social_guard():
    student = type('User', (), {'is_verified': True, 'role': 'student'})()
    assert await require_verified_connect_student(student) is student  # type: ignore[arg-type]


def test_contact_email_rejects_external_inbox():
    with pytest.raises(ValueError):
        normalize_campus_contact_email('advisor@gmail.com')


def test_contact_email_allows_campus_domains():
    assert normalize_campus_contact_email('dean@livingstone.edu') == 'dean@livingstone.edu'
    assert (
        normalize_campus_contact_email('ra@students.livingstone.edu')
        == 'ra@students.livingstone.edu'
    )


async def test_upsert_rejects_external_contact_email(db, factory):
    user = await factory.user(display_name='Staff')
    user.role = 'staff'
    user.email = 'staff.person@livingstone.edu'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()

    with pytest.raises(HTTPException) as exc:
        await upsert_primary_position(
            db,
            user,
            profile,
            CampusPositionCreate(
                category='advising',
                official_title='Advisor',
                department='Student Success',
                contact_email='not-campus@gmail.com',
            ),
        )
    assert exc.value.status_code == 400


async def test_revoked_position_resubmit_returns_to_pending(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    user = await factory.user(display_name='Staff')
    user.role = 'staff'
    user.email = 'resubmit@livingstone.edu'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()

    position = await upsert_primary_position(
        db,
        user,
        profile,
        CampusPositionCreate(
            category='academic',
            official_title='Professor',
            department='Biology',
            contact_email='resubmit@livingstone.edu',
        ),
    )
    await approve_position(db, actor=admin, position_id=position.id)
    await revoke_position(db, actor=admin, position_id=position.id, review_note='Left role')

    updated = await upsert_primary_position(
        db,
        user,
        profile,
        CampusPositionCreate(
            category='academic',
            official_title='Associate Professor',
            department='Biology',
            contact_email='resubmit@livingstone.edu',
        ),
    )
    assert updated.status == 'pending'
    assert updated.official_title == 'Associate Professor'
    assert updated.review_note is None
    assert updated.verified_at is None
