"""Opportunities leave the feed when they close — and undated ones after 60 days — whatever the
viewer's signup date. Employer posts carry a closing date of their own."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError
from sqlalchemy import select

from app.features.campus_hub import content_visibility
from app.features.campus_hub.posts import list_posts
from app.features.campus_hub.publishing import create_post, publish_post
from app.features.campus_hub.schema import CampusPostCreate
from app.features.employers import service as employers_service
from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import CampusPost, EmployerAccount
from app.shared.employer_publishing import summary_of


async def _admin(db, factory):
    admin = await factory.user(display_name='Admin')
    admin.role = 'admin'
    await db.commit()
    return admin


async def _published(db, admin, *, kind, title, published_days_ago, expires_at=None, category=None):
    post = await create_post(
        db,
        actor=admin,
        payload=CampusPostCreate(
            kind=kind, title=title, summary='s', body='b', expires_at=expires_at, category=category
        ),
    )
    await publish_post(db, actor=admin, post_id=post.id)
    post.publish_at = datetime.now(UTC) - timedelta(days=published_days_ago)
    await db.commit()
    return post


async def test_an_undated_opportunity_leaves_the_feed_after_sixty_days(db, factory):
    admin = await _admin(db, factory)
    fresh = await _published(db, admin, kind='opportunity', title='Fresh', published_days_ago=10, category='job')
    stale = await _published(db, admin, kind='opportunity', title='Stale', published_days_ago=61, category='job')
    old_note = await _published(db, admin, kind='announcement', title='Old note', published_days_ago=90)
    student = await factory.user()

    ids = {row['id'] for row in await list_posts(db, user=student)}
    assert fresh.id in ids
    assert stale.id not in ids
    assert old_note.id in ids, 'announcements without a date are not affected'
    assert await content_visibility.is_post_visible(db, stale, user=student) is False


async def test_a_dated_opportunity_follows_its_own_date_even_when_old(db, factory):
    admin = await _admin(db, factory)
    still_open = await _published(
        db, admin, kind='opportunity', title='Long', published_days_ago=90,
        expires_at=datetime.now(UTC) + timedelta(days=5), category='internship',
    )
    student = await factory.user()
    assert still_open.id in {row['id'] for row in await list_posts(db, user=student)}


async def test_employer_posts_close_after_thirty_days_by_default(db, factory):
    admin = await _admin(db, factory)
    org = await employers_service.register_employer(
        db, organization_name='Acme', contact_name='Jamie', contact_email='jobs@acme.com'
    )
    org.status = 'approved'
    org.reviewed_by_id = admin.id
    await db.commit()
    account = (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()

    submission = await employers_service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='Analyst', description='Join us', category='job'),
    )
    post = await db.get(CampusPost, submission.published_post_id)
    expected = datetime.now(UTC) + timedelta(days=30)
    assert abs((post.expires_at - expected).total_seconds()) < 60


def test_an_employer_closing_date_must_be_within_six_months():
    with pytest.raises(ValidationError):
        OpportunitySubmissionCreate(
            title='x', description='y', category='job', closes_at=datetime.now(UTC) + timedelta(days=200)
        )
    with pytest.raises(ValidationError):
        OpportunitySubmissionCreate(
            title='x', description='y', category='job', closes_at=datetime.now(UTC) - timedelta(days=1)
        )


def test_long_descriptions_are_summarised_on_a_word():
    summary = summary_of('word ' * 200)
    assert len(summary) <= 400
    assert summary.endswith('word…')
    assert summary_of('  Short   and sweet ') == 'Short and sweet'
