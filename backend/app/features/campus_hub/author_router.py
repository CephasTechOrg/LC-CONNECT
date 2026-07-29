"""Staff author routes for campus posts — verified publishers only."""

from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_verified_user
from app.features.campus_hub import publishing
from app.features.campus_hub.schema import (
    AuthorCampusPostRead,
    CampusPostCreate,
    CampusPostUpdate,
    PublishingCapabilitiesRead,
)
from app.models import CampusPost, User
from app.shared.rate_limit import campus_post_create_limit, campus_post_publish_limit

router = APIRouter(tags=['campus-hub'])


def _author_read(post: CampusPost) -> AuthorCampusPostRead:
    return AuthorCampusPostRead.model_validate(post)


@router.get('/publishing/capabilities', response_model=PublishingCapabilitiesRead)
async def publishing_capabilities(
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> PublishingCapabilitiesRead:
    enabled = settings.staff_publishing_enabled
    if current_user.role == 'admin':
        return PublishingCapabilitiesRead(can_publish=True, staff_publishing_enabled=enabled)
    if current_user.role != 'staff':
        return PublishingCapabilitiesRead(
            can_publish=False,
            staff_publishing_enabled=enabled,
            reason='Only staff and admins can publish campus posts',
        )
    if not enabled:
        return PublishingCapabilitiesRead(
            can_publish=False,
            staff_publishing_enabled=False,
            reason='Staff publishing is disabled',
        )
    can = await publishing.staff_can_publish(db, current_user)
    return PublishingCapabilitiesRead(
        can_publish=can,
        staff_publishing_enabled=enabled,
        reason=None if can else 'A verified campus position is required before publishing',
    )


@router.get('/my-posts', response_model=list[AuthorCampusPostRead])
async def list_my_posts(
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> list[AuthorCampusPostRead]:
    await publishing.require_staff_publisher(db, current_user)
    posts = await publishing.list_author_posts(db, author_id=current_user.id)
    return [_author_read(post) for post in posts]


@router.post('/my-posts', response_model=AuthorCampusPostRead, status_code=201)
async def create_my_post(
    payload: CampusPostCreate,
    current_user: User = Depends(campus_post_create_limit),
    db: AsyncSession = Depends(get_db),
) -> AuthorCampusPostRead:
    post = await publishing.create_post(db, actor=current_user, payload=payload, as_staff=True)
    return _author_read(post)


@router.patch('/my-posts/{post_id}', response_model=AuthorCampusPostRead)
async def update_my_post(
    post_id: UUID,
    payload: CampusPostUpdate,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> AuthorCampusPostRead:
    post = await publishing.update_post(
        db, actor=current_user, post_id=post_id, payload=payload, as_staff=True
    )
    return _author_read(post)


@router.post('/my-posts/{post_id}/publish', response_model=AuthorCampusPostRead)
async def publish_my_post(
    post_id: UUID,
    background_tasks: BackgroundTasks,
    current_user: User = Depends(campus_post_publish_limit),
    db: AsyncSession = Depends(get_db),
) -> AuthorCampusPostRead:
    post = await publishing.publish_post(db, actor=current_user, post_id=post_id, as_staff=True)
    if publishing.should_push_on_publish(post):
        background_tasks.add_task(publishing.push_published_post, post.id)
    return _author_read(post)


@router.post('/my-posts/{post_id}/archive', response_model=AuthorCampusPostRead)
async def archive_my_post(
    post_id: UUID,
    current_user: User = Depends(require_verified_user),
    db: AsyncSession = Depends(get_db),
) -> AuthorCampusPostRead:
    post = await publishing.archive_post(db, actor=current_user, post_id=post_id, as_staff=True)
    return _author_read(post)
