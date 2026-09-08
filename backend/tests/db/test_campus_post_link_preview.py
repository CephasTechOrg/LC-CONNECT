"""Campus post link_preview appears on public list/detail serializers."""

from __future__ import annotations

from datetime import UTC, datetime

from app.features.admin import campus_posts as posts_admin
from app.features.campus_hub.posts import get_post, list_posts
from app.features.campus_hub.schema import CampusPostCreate, CampusPostSummaryRead
from app.shared.link_preview import LinkPreview, apply_link_preview


async def _admin(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    await db.commit()
    return admin


async def test_published_opportunity_summary_includes_link_preview(db, factory, monkeypatch):
    async def _fake_sync(post):
        apply_link_preview(
            post,
            LinkPreview(
                domain='jobs.example.com',
                site_name='Example Careers',
                title='Summer Intern',
                description='Join our team.',
                image_url='https://jobs.example.com/poster.jpg',
                status='ok',
            ),
        )

    monkeypatch.setattr('app.features.campus_hub.publishing.sync_post_link_preview', _fake_sync)

    admin = await _admin(db, factory)
    post = await posts_admin.create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(
            kind='opportunity',
            title='Summer Intern',
            body='Details inside.',
            category='internship',
            external_url='https://jobs.example.com/posting/1',
        ),
    )
    await posts_admin.publish_post(db, actor=admin, post_id=post.id)

    student = await factory.user(display_name='Student')
    student.role = 'student'
    await db.commit()

    rows = await list_posts(db, user=student, kind='opportunity')
    match = next(row for row in rows if row['id'] == post.id)
    assert match['external_url'] == 'https://jobs.example.com/posting/1'
    assert match['link_preview']['status'] == 'ok'
    assert match['link_preview']['title'] == 'Summer Intern'
    assert match['link_preview']['domain'] == 'jobs.example.com'

    # Response model accepts the nested shape (OpenAPI contract).
    CampusPostSummaryRead.model_validate(match)

    detail = await get_post(db, user=student, post_id=post.id)
    assert detail['link_preview']['image_url'] == 'https://jobs.example.com/poster.jpg'
    assert detail['link_preview']['fetched_at'] is not None
    assert isinstance(detail['link_preview']['fetched_at'], datetime)
    assert detail['link_preview']['fetched_at'].tzinfo is not None
    assert detail['link_preview']['fetched_at'].tzinfo == UTC or detail['link_preview']['fetched_at'].utcoffset()
