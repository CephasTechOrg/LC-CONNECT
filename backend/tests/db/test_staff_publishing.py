"""Delegated staff publishing — verified position required; own posts only."""

from __future__ import annotations

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.admin.campus_positions import approve_position, revoke_position
from app.features.campus_hub import posts as public_posts
from app.features.campus_hub import publishing
from app.features.campus_hub.schema import CampusPostCreate
from app.features.campus_positions.schema import CampusPositionCreate
from app.features.campus_positions.service import get_primary_position, upsert_primary_position
from app.models import Profile


async def _staff_with_verified_position(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    staff = await factory.user(display_name='Publisher')
    staff.role = 'staff'
    staff.email = 'publisher@livingstone.edu'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == staff.id))).scalar_one()
    position = await upsert_primary_position(
        db,
        staff,
        profile,
        CampusPositionCreate(
            category='advising',
            official_title='Advisor',
            department='Student Success',
            contact_email='publisher@livingstone.edu',
        ),
    )
    await approve_position(db, actor=admin, position_id=position.id)
    return admin, staff


async def test_unverified_staff_cannot_publish(db, factory):
    staff = await factory.user(display_name='Pending Staff')
    staff.role = 'staff'
    staff.email = 'pending.pub@livingstone.edu'
    await db.commit()
    profile = (await db.execute(select(Profile).where(Profile.user_id == staff.id))).scalar_one()
    await upsert_primary_position(
        db,
        staff,
        profile,
        CampusPositionCreate(
            category='advising',
            official_title='Advisor',
            department='Student Success',
            contact_email='pending.pub@livingstone.edu',
        ),
    )

    with pytest.raises(HTTPException) as exc:
        await publishing.create_post(
            db,
            actor=staff,
            payload=CampusPostCreate(kind='announcement', title='Hi', body='Body'),
            as_staff=True,
        )
    assert exc.value.status_code == 403


async def test_verified_staff_publishes_and_sees_own_posts(db, factory):
    _, staff = await _staff_with_verified_position(db, factory)
    draft = await publishing.create_post(
        db,
        actor=staff,
        payload=CampusPostCreate(
            kind='opportunity',
            title='RA openings',
            summary='Apply this week',
            body='Details inside.',
            audience='students',
            priority='normal',
        ),
        as_staff=True,
    )
    assert draft.status == 'draft'
    published = await publishing.publish_post(db, actor=staff, post_id=draft.id, as_staff=True)
    assert published.status == 'published'

    mine = await publishing.list_author_posts(db, author_id=staff.id)
    assert any(post.id == published.id for post in mine)


async def test_staff_cannot_set_urgent_priority(db, factory):
    _, staff = await _staff_with_verified_position(db, factory)
    with pytest.raises(HTTPException) as exc:
        await publishing.create_post(
            db,
            actor=staff,
            payload=CampusPostCreate(
                kind='announcement',
                title='Campus closed',
                body='Weather alert',
                priority='urgent',
            ),
            as_staff=True,
        )
    assert exc.value.status_code == 403


async def test_staff_cannot_manage_another_authors_post(db, factory):
    admin, staff_a = await _staff_with_verified_position(db, factory)
    staff_b = await factory.user(display_name='Other Staff')
    staff_b.role = 'staff'
    staff_b.email = 'other.pub@livingstone.edu'
    await db.commit()
    profile_b = (await db.execute(select(Profile).where(Profile.user_id == staff_b.id))).scalar_one()
    position_b = await upsert_primary_position(
        db,
        staff_b,
        profile_b,
        CampusPositionCreate(
            category='academic',
            official_title='Dean',
            department='Arts',
            contact_email='other.pub@livingstone.edu',
        ),
    )
    await approve_position(db, actor=admin, position_id=position_b.id)

    post = await publishing.create_post(
        db,
        actor=staff_a,
        payload=CampusPostCreate(kind='announcement', title='Owned by A', body='Secret'),
        as_staff=True,
    )
    with pytest.raises(HTTPException) as exc:
        await publishing.publish_post(db, actor=staff_b, post_id=post.id, as_staff=True)
    assert exc.value.status_code == 403


async def test_student_cannot_publish(db, factory):
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()
    with pytest.raises(HTTPException) as exc:
        await publishing.create_post(
            db,
            actor=student,
            payload=CampusPostCreate(kind='announcement', title='Nope', body='Nope'),
            as_staff=True,
        )
    assert exc.value.status_code == 403


async def _publish(db, staff, **kwargs):
    payload = CampusPostCreate(kind='announcement', body='Body', **kwargs)
    draft = await publishing.create_post(db, actor=staff, payload=payload, as_staff=True)
    return await publishing.publish_post(db, actor=staff, post_id=draft.id, as_staff=True)


async def _student_sees(db, student, post) -> bool:
    feed = await public_posts.list_posts(db, user=student, limit=200)
    return any(item['id'] == post.id for item in feed)


async def test_published_staff_post_reaches_the_student_feed(db, factory):
    _, staff = await _staff_with_verified_position(db, factory)
    student = await factory.user(display_name='Reader')
    student.role = 'student'
    await db.commit()

    post = await _publish(db, staff, title='Escort hours extended', audience='all')
    assert await _student_sees(db, student, post)

    detail = await public_posts.get_post(db, user=student, post_id=post.id)
    assert detail['title'] == 'Escort hours extended'


async def test_staff_audience_post_is_hidden_from_students(db, factory):
    _, staff = await _staff_with_verified_position(db, factory)
    student = await factory.user(display_name='Reader')
    student.role = 'student'
    await db.commit()

    post = await _publish(db, staff, title='Internal briefing', audience='staff')
    assert not await _student_sees(db, student, post)
    assert await _student_sees(db, staff, post)


async def test_revoke_leaves_published_posts_live_by_default(db, factory):
    admin, staff = await _staff_with_verified_position(db, factory)
    student = await factory.user(display_name='Reader')
    student.role = 'student'
    await db.commit()
    post = await _publish(db, staff, title='Term-end notice', audience='all')
    position = await get_primary_position(db, staff.id)

    await revoke_position(db, actor=admin, position_id=position.id, review_note='Term ended')

    await db.refresh(post)
    assert post.status == 'published'
    assert await _student_sees(db, student, post)


async def test_revoke_with_archive_posts_pulls_them_from_the_feed(db, factory):
    admin, staff = await _staff_with_verified_position(db, factory)
    student = await factory.user(display_name='Reader')
    student.role = 'student'
    await db.commit()
    post = await _publish(db, staff, title='Fraudulent notice', audience='all')
    draft = await publishing.create_post(
        db,
        actor=staff,
        payload=CampusPostCreate(kind='announcement', title='Unsent', body='Body'),
        as_staff=True,
    )
    position = await get_primary_position(db, staff.id)

    await revoke_position(
        db, actor=admin, position_id=position.id, review_note='Fraudulent', archive_posts=True
    )

    await db.refresh(post)
    await db.refresh(draft)
    assert post.status == 'archived'
    assert not await _student_sees(db, student, post)
    # Drafts are untouched: already invisible, and republishing needs a position they lost.
    assert draft.status == 'draft'
