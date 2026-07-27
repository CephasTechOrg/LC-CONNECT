from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin_aal2
from app.features.admin import campus_positions as campus_admin
from app.features.admin import campus_posts as posts_admin
from app.features.admin import campus_resources as resources_admin
from app.features.admin.schema import (
    AdminUserRead,
    CampusPositionAdminRead,
    CampusPostAdminRead,
    CampusResourceAdminRead,
    PositionReviewRequest,
    SuspendUserRequest,
)
from app.features.admin.service import remove_activity as do_remove_activity
from app.features.admin.service import suspend_user as do_suspend_user
from app.features.campus_hub.schema import (
    CampusPostCreate,
    CampusPostUpdate,
    CampusResourceCreate,
    CampusResourceUpdate,
)
from app.features.campus_positions.schema import CampusPositionRead
from app.features.notifications.push import push_sender
from app.models import Profile, Report, User
from app.shared.schemas import ReportRead

router = APIRouter(prefix='/admin', tags=['admin'])


def _position_admin_read(position, user: User, profile: Profile) -> CampusPositionAdminRead:
    base = CampusPositionRead.model_validate(position).model_dump()
    return CampusPositionAdminRead(
        **base,
        user_email=user.email,
        user_role=user.role,
        display_name=profile.display_name,
    )


@router.get('/users', response_model=list[AdminUserRead])
async def list_users(_: User = Depends(require_admin_aal2), db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(User, Profile)
        .join(Profile, Profile.user_id == User.id)
        .order_by(User.created_at.desc())
        .limit(200)
    )
    return [
        AdminUserRead(
            id=user.id,
            email=user.email,
            role=user.role,
            status=user.status,
            is_active=user.is_active,
            is_verified=user.is_verified,
            display_name=profile.display_name,
        )
        for user, profile in result.all()
    ]


@router.get('/reports', response_model=list[ReportRead])
async def list_reports(_: User = Depends(require_admin_aal2), db: AsyncSession = Depends(get_db)):
    return list((await db.execute(select(Report).order_by(Report.created_at.desc()).limit(200))).scalars().all())


@router.get('/campus-positions/pending', response_model=list[CampusPositionAdminRead])
async def list_pending_campus_positions(
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[CampusPositionAdminRead]:
    rows = await campus_admin.list_pending_positions(db)
    return [_position_admin_read(position, user, profile) for position, user, profile in rows]


@router.get('/campus-positions/{position_id}', response_model=CampusPositionAdminRead)
async def get_campus_position(
    position_id: UUID,
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionAdminRead:
    position, user, profile = await campus_admin.get_position_detail(db, position_id)
    return _position_admin_read(position, user, profile)


@router.post('/campus-positions/{position_id}/approve', response_model=CampusPositionRead)
async def approve_campus_position(
    position_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionRead:
    position = await campus_admin.approve_position(db, actor=actor, position_id=position_id)
    return CampusPositionRead.model_validate(position)


@router.post('/campus-positions/{position_id}/reject', response_model=CampusPositionRead)
async def reject_campus_position(
    position_id: UUID,
    payload: PositionReviewRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionRead:
    position = await campus_admin.reject_position(
        db,
        actor=actor,
        position_id=position_id,
        review_note=payload.review_note,
    )
    return CampusPositionRead.model_validate(position)


@router.post('/campus-positions/{position_id}/revoke', response_model=CampusPositionRead)
async def revoke_campus_position(
    position_id: UUID,
    payload: PositionReviewRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionRead:
    position = await campus_admin.revoke_position(
        db,
        actor=actor,
        position_id=position_id,
        review_note=payload.review_note,
    )
    return CampusPositionRead.model_validate(position)


async def _push_published_post(post_id: UUID) -> None:
    from app.database import AsyncSessionLocal
    from app.models import CampusPost

    async with AsyncSessionLocal() as db:
        post = await db.get(CampusPost, post_id)
        if post is None or post.status != 'published':
            return
        if post.priority not in {'important', 'urgent'}:
            return
        tokens = await posts_admin.recipient_tokens_for_post(db, post)
        if tokens:
            await push_sender.notify_campus_post(
                db,
                tokens=tokens,
                title=post.title,
                post_id=post.id,
                priority=post.priority,
            )


@router.get('/campus-posts', response_model=list[CampusPostAdminRead])
async def list_campus_posts(
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[CampusPostAdminRead]:
    posts = await posts_admin.list_posts(db)
    return [CampusPostAdminRead.model_validate(post) for post in posts]


@router.post('/campus-posts', response_model=CampusPostAdminRead, status_code=201)
async def create_campus_post(
    payload: CampusPostCreate,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.create_post(db, actor=actor, payload=payload)
    return CampusPostAdminRead.model_validate(post)


@router.patch('/campus-posts/{post_id}', response_model=CampusPostAdminRead)
async def update_campus_post(
    post_id: UUID,
    payload: CampusPostUpdate,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.update_post(db, actor=actor, post_id=post_id, payload=payload)
    return CampusPostAdminRead.model_validate(post)


@router.post('/campus-posts/{post_id}/publish', response_model=CampusPostAdminRead)
async def publish_campus_post(
    post_id: UUID,
    background_tasks: BackgroundTasks,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.publish_post(db, actor=actor, post_id=post_id)
    # Only fan out push for posts that are live now — scheduled posts wait for a future job.
    now = datetime.now(UTC)
    is_live = post.publish_at is not None and post.publish_at <= now
    if post.priority in {'important', 'urgent'} and is_live:
        background_tasks.add_task(_push_published_post, post.id)
    return CampusPostAdminRead.model_validate(post)


@router.post('/campus-posts/{post_id}/archive', response_model=CampusPostAdminRead)
async def archive_campus_post(
    post_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.archive_post(db, actor=actor, post_id=post_id)
    return CampusPostAdminRead.model_validate(post)


@router.get('/campus-resources', response_model=list[CampusResourceAdminRead])
async def list_campus_resources(
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[CampusResourceAdminRead]:
    resources = await resources_admin.list_resources(db)
    return [CampusResourceAdminRead.model_validate(resource) for resource in resources]


@router.post('/campus-resources', response_model=CampusResourceAdminRead, status_code=201)
async def create_campus_resource(
    payload: CampusResourceCreate,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusResourceAdminRead:
    resource = await resources_admin.create_resource(db, actor=actor, payload=payload)
    return CampusResourceAdminRead.model_validate(resource)


@router.patch('/campus-resources/{resource_id}', response_model=CampusResourceAdminRead)
async def update_campus_resource(
    resource_id: UUID,
    payload: CampusResourceUpdate,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusResourceAdminRead:
    resource = await resources_admin.update_resource(db, actor=actor, resource_id=resource_id, payload=payload)
    return CampusResourceAdminRead.model_validate(resource)


@router.post('/users/{user_id}/suspend')
async def suspend_user(
    user_id: UUID,
    payload: SuspendUserRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    user = await do_suspend_user(db, user_id, actor_id=actor.id)
    return {'status': 'suspended', 'user_id': str(user.id), 'reason': payload.reason}


@router.post('/activities/{activity_id}/remove')
async def remove_activity(
    activity_id: UUID,
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    activity = await do_remove_activity(db, activity_id)
    return {'status': 'removed', 'activity_id': str(activity.id)}
