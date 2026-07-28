"""Public campus directory — Campus Hub Phase 4."""

from __future__ import annotations

from sqlalchemy import select

from app.features.admin.campus_positions import approve_position
from app.features.campus_hub.service import get_directory_entry, list_directory, list_students
from app.features.campus_positions.schema import CampusPositionCreate
from app.features.campus_positions.service import upsert_primary_position
from app.models import Profile


async def _verified_staff(db, factory, *, title: str = 'Academic Advisor'):
    user = await factory.user(display_name='Directory Staff')
    user.email = 'dir.staff@livingstone.edu'
    user.role = 'staff'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == user.id))).scalar_one()
    profile.display_name = 'Directory Staff'
    await db.commit()
    position = await upsert_primary_position(
        db,
        user,
        profile,
        CampusPositionCreate(
            category='advising',
            official_title=title,
            department='Student Success',
            contact_email='dir.staff@livingstone.edu',
        ),
    )
    return user, profile, position


async def test_pending_position_not_in_directory(db, factory):
    _, _, position = await _verified_staff(db, factory)
    rows = await list_directory(db)
    assert all(row['position_id'] != position.id for row in rows)


async def test_verified_position_appears_in_directory(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    user, _, position = await _verified_staff(db, factory, title='Professor')
    await approve_position(db, actor=admin, position_id=position.id)

    rows = await list_directory(db)
    match = next((row for row in rows if row['position_id'] == position.id), None)
    assert match is not None
    assert match['official_title'] == 'Professor'
    assert match['user_id'] == user.id


async def test_student_directory_lists_students_not_self_or_hidden(db, factory):
    staff, _, _ = await _verified_staff(db, factory)
    visible = await factory.user(display_name='Visible Student')  # role defaults to student
    hidden = await factory.user(display_name='Hidden Student')
    hidden_profile = (await db.execute(select(Profile).where(Profile.user_id == hidden.id))).scalar_one()
    hidden_profile.is_hidden = True
    await db.commit()

    rows = await list_students(db, exclude_user_id=staff.id)
    ids = {row['user_id'] for row in rows}
    assert visible.id in ids  # students show up for staff
    assert hidden.id not in ids  # hidden profiles are respected
    assert staff.id not in ids  # never list the caller


async def test_student_directory_search_matches_name(db, factory):
    staff, _, _ = await _verified_staff(db, factory)
    await factory.user(display_name='Zaraah Okoye')
    await factory.user(display_name='Ben Carter')

    rows = await list_students(db, exclude_user_id=staff.id, query='zaraah')
    names = {row['display_name'] for row in rows}
    assert 'Zaraah Okoye' in names
    assert 'Ben Carter' not in names


async def test_directory_filters_by_category(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    _, _, position = await _verified_staff(db, factory)
    await approve_position(db, actor=admin, position_id=position.id)

    rows = await list_directory(db, category='advising')
    assert any(row['position_id'] == position.id for row in rows)
    assert all(row['category'] == 'advising' for row in rows)

    other = await list_directory(db, category='academic')
    assert all(row['position_id'] != position.id for row in other)


async def test_directory_detail_requires_verified_position(db, factory):
    import pytest
    from fastapi import HTTPException

    _, _, position = await _verified_staff(db, factory)
    with pytest.raises(HTTPException) as exc:
        await get_directory_entry(db, position.id)
    assert exc.value.status_code == 404

    admin = await factory.user(display_name='Admin2')
    admin.role = 'admin'
    await approve_position(db, actor=admin, position_id=position.id)
    detail = await get_directory_entry(db, position.id)
    assert detail['official_title'] == 'Academic Advisor'


async def test_suspended_user_not_in_directory(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    user, _, position = await _verified_staff(db, factory)
    await approve_position(db, actor=admin, position_id=position.id)
    user.status = 'suspended'
    user.is_active = False
    await db.commit()

    rows = await list_directory(db)
    assert all(row['position_id'] != position.id for row in rows)
