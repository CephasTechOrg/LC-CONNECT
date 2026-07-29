"""Campus Hub Phase 5 — posts, resources, overview, and admin publishing."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException

from app.features.admin.campus_posts import archive_post, create_post, delete_post, publish_post
from app.features.admin.campus_resources import create_resource, delete_resource
from app.features.campus_hub import publishing
from app.features.campus_hub.posts import (
    announcement_total,
    build_overview,
    get_post,
    list_posts,
    mark_all_announcements_read,
    mark_announcement_read,
    unread_announcement_count,
)
from app.features.campus_hub.resources import get_resource, list_resources
from app.features.campus_hub.schema import CampusPostCreate, CampusPostUpdate, CampusResourceCreate


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
        payload=CampusPostCreate(kind='announcement', title='Draft', body='Hidden body'),
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
            kind='announcement',
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
            kind='announcement',
            title='Past deadline',
            body='Already passed.',
            expires_at=datetime.now(UTC) - timedelta(hours=1),
        ),
    )
    await publish_post(db, actor=admin, post_id=post.id)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    rows = await list_posts(db, user=student, kind='announcement')
    assert all(row['id'] != post.id for row in rows)


async def test_overview_groups_content(db, factory):
    admin = await _admin(db, factory)
    # Urgency is a priority, not a kind — an urgent announcement is the alert banner.
    urgent = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='announcement', title='Weather alert', body='Campus closed.', priority='urgent'),
    )
    update = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='announcement', title='Library hours', body='Extended hours this week.'),
    )
    for item in (urgent, update):
        await publish_post(db, actor=admin, post_id=item.id)

    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    overview = await build_overview(db, user=student)
    assert any(row['id'] == urgent.id for row in overview['urgent_posts'])
    assert any(row['id'] == update.id for row in overview['latest_updates'])
    assert 'upcoming_deadlines' not in overview  # deadlines are gone


async def test_archive_removes_post_from_feed(db, factory):
    admin = await _admin(db, factory)
    post = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(kind='announcement', title='Temporary', body='Will archive.'),
    )
    await publish_post(db, actor=admin, post_id=post.id)
    await archive_post(db, actor=admin, post_id=post.id)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await get_post(db, user=student, post_id=post.id)
    assert exc.value.status_code == 404


async def _published_announcement(db, admin, *, title='Note', audience='all'):
    post = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title=title, body='Body', audience=audience),
    )
    await publish_post(db, actor=admin, post_id=post.id)
    return post


async def test_announcement_unread_count_decrements_per_read(db, factory):
    admin = await _admin(db, factory)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()
    a1 = await _published_announcement(db, admin, title='A1')
    a2 = await _published_announcement(db, admin, title='A2')

    assert await unread_announcement_count(db, student) == 2

    await mark_announcement_read(db, student, a1.id)
    assert await unread_announcement_count(db, student) == 1  # reading one takes one off

    await mark_announcement_read(db, student, a1.id)  # again → idempotent
    assert await unread_announcement_count(db, student) == 1

    await mark_all_announcements_read(db, student)
    assert await unread_announcement_count(db, student) == 0
    # a2 was covered by mark-all
    assert a2.id is not None


async def test_announcement_unread_respects_audience(db, factory):
    admin = await _admin(db, factory)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()
    await _published_announcement(db, admin, title='Staff only', audience='staff')

    # A staff-audience announcement is not visible to a student, so it never counts as unread.
    assert await unread_announcement_count(db, student) == 0


async def test_category_must_be_a_known_value(db, factory):
    admin = await _admin(db, factory)
    with pytest.raises(ValueError):
        CampusPostCreate(kind='announcement', title='Bad', body='Body', category='made_up')

    # Known categories are accepted and persist.
    post = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='Good', body='Body', category='safety'),
    )
    assert post.category == 'safety'


async def test_opportunity_and_announcement_categories_do_not_cross(db, factory):
    """Each kind has its own category vocabulary — an opportunity category on an announcement
    (and vice versa) must be rejected, not silently accepted."""
    admin = await _admin(db, factory)

    # An opportunity category is invalid for an announcement.
    with pytest.raises(ValueError):
        CampusPostCreate(kind='announcement', title='Bad', body='Body', category='internship')

    # An announcement category is invalid for an opportunity.
    with pytest.raises(ValueError):
        CampusPostCreate(kind='opportunity', title='Bad', body='Body', category='safety')

    # Each kind accepts its own vocabulary.
    opportunity = await create_post(
        db, actor=admin,
        payload=CampusPostCreate(kind='opportunity', title='Intern wanted', body='Body', category='internship'),
    )
    assert opportunity.category == 'internship'


async def test_update_post_validates_category_against_resolved_kind(db, factory):
    """On a partial update, `kind` may be absent from the payload — validation must use the
    post's *existing* kind, not silently skip the check."""
    admin = await _admin(db, factory)
    announcement = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='Note', body='Body', category='general'),
    )

    # category-only update: no kind in the payload — must still validate against 'announcement'.
    with pytest.raises(HTTPException) as exc:
        await publishing.update_post(
            db, actor=admin, post_id=announcement.id, payload=CampusPostUpdate(category='internship'), as_staff=False,
        )
    assert exc.value.status_code == 400

    # A valid announcement category still updates fine.
    updated = await publishing.update_post(
        db, actor=admin, post_id=announcement.id, payload=CampusPostUpdate(category='safety'), as_staff=False,
    )
    assert updated.category == 'safety'


async def test_announcement_total_counts_and_filters_by_category(db, factory):
    admin = await _admin(db, factory)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    p1 = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='A', body='B', category='safety'),
    )
    await publish_post(db, actor=admin, post_id=p1.id)
    p2 = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='B', body='B', category='academic'),
    )
    await publish_post(db, actor=admin, post_id=p2.id)

    assert await announcement_total(db, student) == 2
    assert await announcement_total(db, student, category='safety') == 1
    assert await announcement_total(db, student, category='events') == 0


async def test_list_posts_reports_read_state_per_user(db, factory):
    admin = await _admin(db, factory)
    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()
    post = await _published_announcement(db, admin, title='Read me')

    unread_rows = await list_posts(db, user=student, kind='announcement')
    assert unread_rows[0]['read'] is False

    await mark_announcement_read(db, student, post.id)
    read_rows = await list_posts(db, user=student, kind='announcement')
    assert read_rows[0]['read'] is True


async def test_admin_can_delete_post(db, factory):
    admin = await _admin(db, factory)
    post = await create_post(
        db, actor=admin, payload=CampusPostCreate(kind='announcement', title='Temp', body='Body'),
    )
    await delete_post(db, actor=admin, post_id=post.id)
    with pytest.raises(HTTPException) as exc:
        await get_post(db, user=admin, post_id=post.id)
    assert exc.value.status_code == 404


async def test_admin_can_delete_resource(db, factory):
    admin = await _admin(db, factory)
    resource = await create_resource(
        db,
        actor=admin,
        payload=CampusResourceCreate(category='advising', title='Temp desk', description='Gone soon.'),
    )
    await delete_resource(db, actor=admin, resource_id=resource.id)
    with pytest.raises(HTTPException) as exc:
        await get_resource(db, resource.id)
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
