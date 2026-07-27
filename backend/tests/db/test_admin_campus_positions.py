"""Admin campus position review — Campus Hub Phase 3."""

from __future__ import annotations

from sqlalchemy import func, select

from app.features.admin import campus_positions as campus_admin
from app.features.campus_positions.schema import CampusPositionCreate
from app.features.campus_positions.service import upsert_primary_position
from app.models import AdminAuditLog, Profile


async def _staff_with_position(db, factory, *, title: str = 'Advisor'):
    user = await factory.user(display_name='Staff Member')
    user.email = f'{title.lower().replace(" ", ".")}@livingstone.edu'
    user.role = 'staff'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    profile.display_name = 'Staff Member'
    await db.commit()
    position = await upsert_primary_position(
        db,
        user,
        profile,
        CampusPositionCreate(
            category='advising',
            official_title=title,
            department='Student Success',
        ),
    )
    return user, profile, position


async def test_list_pending_positions(db, factory):
    _, _, position = await _staff_with_position(db, factory)
    rows = await campus_admin.list_pending_positions(db)
    assert any(row[0].id == position.id for row in rows)


async def test_approve_position_writes_audit_and_verifies(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    _, _, position = await _staff_with_position(db, factory, title='Professor')

    approved = await campus_admin.approve_position(db, actor=admin, position_id=position.id)
    assert approved.status == 'verified'
    assert approved.verified_by_id == admin.id
    assert approved.verified_at is not None

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(
                AdminAuditLog.action == 'campus_position.approve',
                AdminAuditLog.target_id == position.id,
            )
        )
    ).scalar_one()
    assert audit_count == 1


async def test_reject_position_sets_note(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    _, _, position = await _staff_with_position(db, factory, title='Coordinator')

    rejected = await campus_admin.reject_position(
        db,
        actor=admin,
        position_id=position.id,
        review_note='Title could not be verified',
    )
    assert rejected.status == 'rejected'
    assert rejected.review_note == 'Title could not be verified'


async def test_revoke_verified_position(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    _, _, position = await _staff_with_position(db, factory, title='Director')
    await campus_admin.approve_position(db, actor=admin, position_id=position.id)

    revoked = await campus_admin.revoke_position(
        db,
        actor=admin,
        position_id=position.id,
        review_note='No longer in this role',
    )
    assert revoked.status == 'revoked'


async def test_non_pending_cannot_be_approved(db, factory):
    import pytest
    from fastapi import HTTPException

    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    _, _, position = await _staff_with_position(db, factory)
    await campus_admin.reject_position(db, actor=admin, position_id=position.id, review_note='nope')

    with pytest.raises(HTTPException) as exc:
        await campus_admin.approve_position(db, actor=admin, position_id=position.id)
    assert exc.value.status_code == 409
