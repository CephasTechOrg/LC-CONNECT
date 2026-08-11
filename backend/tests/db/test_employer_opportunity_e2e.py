"""End-to-end: an employer posts an opportunity and the right students actually see it.

Auto-publish replaced the admin review step, so the whole chain now runs without an admin in the
loop. Existing coverage only exercised the *manual* approve path — this walks the real one:
employer submits -> post publishes -> eligible scholar sees it in the feed -> everyone else does
not.
"""

from __future__ import annotations

from sqlalchemy import select

from app.features.campus_hub import content_visibility
from app.features.employers import service as employers_service
from app.features.employers.schema import OpportunitySubmissionCreate
from app.models import CampusPost, EmployerAccount, Program, ProgramMembership


async def _honors_admin(db, factory):
    admin = await factory.user(display_name='Honors Admin')
    admin.role = 'admin'
    await db.commit()
    return admin


async def _approved_employer(db, approver, *, email='partner@acme.com') -> EmployerAccount:
    org = await employers_service.register_employer(
        db, organization_name='Acme Corp', contact_name='Jamie', contact_email=email
    )
    org.status = 'approved'
    org.reviewed_by_id = approver.id
    await db.commit()
    return (
        await db.execute(select(EmployerAccount).where(EmployerAccount.organization_id == org.id))
    ).scalar_one()


async def _scholar(db, factory, *, active=True, name='Scholar'):
    user = await factory.user(display_name=name)
    program = (
        await db.execute(select(Program).where(Program.slug == 'presidential_scholars'))
    ).scalar_one_or_none()
    if program is None:
        program = Program(slug='presidential_scholars', name='Presidential Scholars')
        db.add(program)
        await db.flush()
    db.add(ProgramMembership(
        user_id=user.id, program_id=program.id, status='active' if active else 'revoked'
    ))
    await db.commit()
    return user


async def _feed_ids(db, user) -> set:
    rows = (await db.execute(content_visibility.published_posts_stmt(user=user))).scalars().all()
    return {p.id for p in rows}


async def test_employer_post_reaches_an_eligible_scholars_feed(db, factory):
    """The headline path: nobody approves anything, and the scholar still sees it."""
    admin = await _honors_admin(db, factory)
    account = await _approved_employer(db, admin)
    scholar = await _scholar(db, factory)

    submission = await employers_service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(
            title='Summer Analyst', description='Join our team', category='internship'
        ),
    )
    assert submission.status == 'approved'

    post = await db.get(CampusPost, submission.published_post_id)
    assert post.status == 'published'
    assert post.kind == 'opportunity'
    # Drives the "Employer Partner" badge students see on the card.
    assert post.source == 'employer'

    assert await content_visibility.is_post_visible(db, post, user=scholar) is True
    assert post.id in await _feed_ids(db, scholar)


async def test_plain_student_never_sees_an_employer_opportunity(db, factory):
    """Enforced in the query itself, not hidden client-side."""
    admin = await _honors_admin(db, factory)
    account = await _approved_employer(db, admin)
    plain = await factory.user(display_name='Plain Student')

    submission = await employers_service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='Analyst', description='x', category='internship'),
    )
    post = await db.get(CampusPost, submission.published_post_id)

    assert await content_visibility.is_post_visible(db, post, user=plain) is False
    assert post.id not in await _feed_ids(db, plain)


async def test_revoked_scholar_loses_access_immediately(db, factory):
    """Membership is re-evaluated per request — revoking removes the post on the very next read."""
    admin = await _honors_admin(db, factory)
    account = await _approved_employer(db, admin)
    scholar = await _scholar(db, factory)

    submission = await employers_service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='Analyst', description='x', category='internship'),
    )
    post = await db.get(CampusPost, submission.published_post_id)
    assert post.id in await _feed_ids(db, scholar)

    membership = (
        await db.execute(select(ProgramMembership).where(ProgramMembership.user_id == scholar.id))
    ).scalar_one()
    membership.status = 'revoked'
    await db.commit()

    assert post.id not in await _feed_ids(db, scholar)


async def test_taken_down_post_disappears_from_the_feed(db, factory):
    """Reactive moderation is the safety net that replaced pre-publication review, so archiving
    must genuinely remove it from what students see."""
    from app.features.admin import campus_posts as posts_admin

    admin = await _honors_admin(db, factory)
    account = await _approved_employer(db, admin)
    scholar = await _scholar(db, factory)

    submission = await employers_service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='Bad Post', description='x', category='job'),
    )
    post_id = submission.published_post_id
    assert post_id in await _feed_ids(db, scholar)

    await posts_admin.archive_post(db, actor=admin, post_id=post_id)
    assert post_id not in await _feed_ids(db, scholar)


# ── push audience must match feed audience ───────────────────────────────────────


async def test_push_for_a_programme_post_excludes_non_members(db, factory):
    """`recipient_tokens_for_post` previously filtered only on audience/role, ignoring
    `eligible_program_slug`. Any programme-restricted post that ever became important/urgent would
    have paged the whole campus about something only scholars can open — leaking its title. Not
    reachable today (employer posts default to priority='normal'), so this pins the invariant
    before some future change makes it reachable."""
    from app.features.campus_hub.publishing import recipient_tokens_for_post
    from app.models import DeviceToken

    admin = await _honors_admin(db, factory)
    account = await _approved_employer(db, admin)
    scholar = await _scholar(db, factory, name='Scholar With Phone')
    plain = await factory.user(display_name='Plain With Phone')

    db.add(DeviceToken(user_id=scholar.id, token='tok-scholar', platform='ios'))
    db.add(DeviceToken(user_id=plain.id, token='tok-plain', platform='ios'))
    await db.commit()

    submission = await employers_service.submit_opportunity(
        db, account=account,
        payload=OpportunitySubmissionCreate(title='Analyst', description='x', category='internship'),
    )
    post = await db.get(CampusPost, submission.published_post_id)

    tokens = await recipient_tokens_for_post(db, post)
    assert 'tok-scholar' in tokens
    assert 'tok-plain' not in tokens


async def test_push_for_an_ordinary_post_still_reaches_everyone(db, factory):
    """The eligibility filter must only narrow programme-restricted posts — a normal campus
    announcement still goes to the whole audience."""
    from app.features.campus_hub.publishing import recipient_tokens_for_post
    from app.models import DeviceToken

    admin = await _honors_admin(db, factory)
    plain = await factory.user(display_name='Plain With Phone')
    db.add(DeviceToken(user_id=plain.id, token='tok-plain', platform='ios'))
    post = CampusPost(
        author_id=admin.id, kind='announcement', title='Campus closed', body='...',
        status='published', audience='all', priority='important',
    )
    db.add(post)
    await db.commit()

    assert 'tok-plain' in await recipient_tokens_for_post(db, post)
