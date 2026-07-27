"""Campus Hub Phase 5 — posts, resources, overview, and admin publishing."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.features.admin.campus_posts import archive_post, create_post, publish_post
from app.features.admin.campus_resources import create_resource
from app.features.campus_hub.posts import build_overview, get_post, list_posts
from app.features.campus_hub.resources import get_resource, list_resources
from app.features.campus_hub.schema import CampusPostCreate, CampusResourceCreate


async def _admin(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    await db.commit()
    return admin


async def test_draft_post_not_public(db, factory):
    admin = await _admin(db, factory)
    post = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='update', title='Draft', body='Hidden body'),
    )
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    rows = await list_posts(db, user=student)
    assert all(row['id'] != post.id for row in rows)


async def test_published_post_visible_to_audience(db, factory):
    admin = await _admin(db, factory)
    post = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(
            kind='update',
            title='Welcome back',
            summary='Fall semester kickoff',
            body='Classes begin Monday.',
            audience='students',
            priority='normal',
        ),
    )
    await publish_post(db, actor=admin, post_id=post.id)

    student = await factory.user(display_name='Student')
    student.role = 'student'
    staff = await factory.user(display_name='Staff')
    staff.role = 'staff'
    await db.commit()

    student_rows = await list_posts(db, user=student)
    staff_rows = await list_posts(db, user=staff)
    assert any(row['id'] == post.id for row in student_rows)
    assert all(row['id'] != post.id for row in staff_rows)


async def test_expired_post_hidden(db, factory):
    admin = await _admin(db, factory)
    post = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(
            kind='deadline',
            title='Past deadline',
            body='Already passed.',
            expires_at=datetime.now(UTC) - timedelta(hours=1),
        ),
    )
    await publish_post(db, actor=admin, post_id=post.id)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    rows = await list_posts(db, user=student, kind='deadline')
    assert all(row['id'] != post.id for row in rows)


async def test_overview_groups_content(db, factory):
    admin = await _admin(db, factory)
    urgent = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='alert', title='Weather alert', body='Campus closed.', priority='urgent'),
    )
    update = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='update', title='Library hours', body='Extended hours this week.'),
    )
    deadline = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='deadline', title='FAFSA due', body='Submit by Friday.'),
    )
    for item in (urgent, update, deadline):
        await publish_post(db, actor=admin, post_id=item.id)

    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    overview = await build_overview(db, user=student)
    assert any(row['id'] == urgent.id for row in overview['urgent_posts'])
    assert any(row['id'] == update.id for row in overview['latest_updates'])
    assert any(row['id'] == deadline.id for row in overview['upcoming_deadlines'])


async def test_archive_removes_post_from_feed(db, factory):
    admin = await _admin(db, factory)
    post = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='update', title='Temporary', body='Will archive.'),
    )
    await publish_post(db, actor=admin, post_id=post.id)
    await archive_post(db, actor=admin, post_id=post.id)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await get_post(db, user=student, post_id=post.id)
    assert exc.value.status_code == 404


async def test_resources_list_active_only(db, factory):
    admin = await _admin(db, factory)
    active = await create_resource(
        db,
        actor=admin,
        payload=CampusResourceCreate(
            category='safety',
            title='Campus Safety',
            description='24/7 security desk.',
            sort_order=1,
        ),
    )
    inactive = await create_resource(
        db,
        actor=admin,
        payload=CampusResourceCreate(
            category='other',
            title='Old office',
            description='Retired listing.',
            is_active=False,
        ),
    )

    rows = await list_resources(db)
    ids = {row['id'] for row in rows}
    assert active.id in ids
    assert inactive.id not in ids

    detail = await get_resource(db, active.id)
    assert detail['title'] == 'Campus Safety'

    with pytest.raises(HTTPException) as exc:
        await get_resource(db, inactive.id)
    assert exc.value.status_code == 404
