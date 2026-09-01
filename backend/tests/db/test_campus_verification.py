"""Admin campus verification — badge grant/revoke and public profile badge mapping."""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.admin import campus_verification as campus_service
from app.features.discovery.router import get_discovery_cards
from app.models import AdminAuditLog, Profile, User
from app.shared.serializers import profile_to_public


async def test_campus_verify_sets_fields_and_audits(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Student', is_verified=True)
    student.role = 'student'
    await db.commit()

    result = await campus_service.campus_verify_user(db, student.id, actor_id=admin.id)
    assert result.campus_verified is True
    assert result.campus_verified_by_id == admin.id
    assert result.campus_verified_at is not None

    audit = (
        await db.execute(
            select(AdminAuditLog).where(
                AdminAuditLog.action == 'user.campus_verify',
                AdminAuditLog.target_id == student.id,
            )
        )
    ).scalar_one()
    assert audit.actor_id == admin.id


async def test_campus_verify_requires_email_confirmed(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Student', is_verified=False)
    student.role = 'student'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await campus_service.campus_verify_user(db, student.id, actor_id=admin.id)
    assert exc.value.status_code == 422


async def test_campus_verify_is_idempotent_guard(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Student', is_verified=True, campus_verified=True)
    student.role = 'student'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await campus_service.campus_verify_user(db, student.id, actor_id=admin.id)
    assert exc.value.status_code == 409


async def test_revoke_campus_verification_clears_fields(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Student', is_verified=True, campus_verified=True)
    student.campus_verified_by_id = admin.id
    student.role = 'student'
    await db.commit()

    result = await campus_service.revoke_campus_verification(
        db, student.id, actor_id=admin.id, reason='Test revoke'
    )
    assert result.campus_verified is False
    assert result.campus_verified_at is None
    assert result.campus_verified_by_id is None

    audit = (
        await db.execute(
            select(AdminAuditLog).where(
                AdminAuditLog.action == 'user.campus_verify_revoke',
                AdminAuditLog.target_id == student.id,
            )
        )
    ).scalar_one()
    assert audit.actor_id == admin.id


async def test_revoke_when_not_verified_is_409(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    student = await factory.user(display_name='Student', is_verified=True)
    student.role = 'student'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await campus_service.revoke_campus_verification(db, student.id, actor_id=admin.id)
    assert exc.value.status_code == 409


async def test_profile_badge_uses_campus_verified_not_email_otp(db, factory):
    student = await factory.user(display_name='Student', is_verified=True, campus_verified=False)
    profile = (await db.execute(select(Profile).where(Profile.user_id == student.id))).scalar_one()
    public = profile_to_public(profile)
    assert public.is_verified is False

    student.campus_verified = True
    await db.commit()
    await db.refresh(student)
    public = profile_to_public(profile)
    assert public.is_verified is True


async def test_discovery_card_badge_follows_campus_verified(db, factory):
    student = await factory.user(display_name='Student A')
    student.role = 'student'
    student.campus_verified = True
    student_profile = (await db.execute(select(Profile).where(Profile.user_id == student.id))).scalar_one()
    student_profile.major = 'Biology'
    student_profile.class_year = 2027
    from app.models import LookingForOption

    option = LookingForOption(code='friendship', name='Friendship')
    db.add(option)
    await db.flush()
    student_profile.looking_for_options = [option]
    student_profile.profile_completed = True
    await db.commit()

    viewer = await factory.user(display_name='Viewer')
    viewer.role = 'student'
    await db.commit()

    cards = await get_discovery_cards(current_user=viewer, db=db, limit=20)
    student_card = next(card for card in cards if card.user_id == student.id)
    assert student_card.is_verified is True


async def test_campus_verify_unknown_user_404(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    await db.commit()
    with pytest.raises(HTTPException) as exc:
        await campus_service.campus_verify_user(db, uuid4(), actor_id=admin.id)
    assert exc.value.status_code == 404
