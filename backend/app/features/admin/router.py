from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin_aal2
from app.features.admin import campus_positions as campus_admin
from app.features.admin import campus_posts as posts_admin
from app.features.admin import campus_resources as resources_admin
from app.features.admin import programs as programs_admin
from app.features.admin.schema import (
    AdminUserRead,
    CampusPositionAdminRead,
    CampusPostAdminRead,
    CampusResourceAdminRead,
    PositionReviewRequest,
    PositionRevokeRequest,
    ProgramMembershipAdminRead,
    ProgramMembershipRevokeRequest,
    ProgramMembershipVerifyRequest,
    SuspendUserRequest,
)
from app.features.admin.service import remove_activity as do_remove_activity
from app.features.admin.service import suspend_user as do_suspend_user
from app.features.campus_hub import publishing
from app.features.campus_hub.schema import (
    CampusPostCreate,
    CampusPostUpdate,
    CampusResourceCreate,
    CampusResourceUpdate,
)
from app.features.campus_positions.schema import CampusPositionRead
from app.models import Profile, Report, User
from app.shared.profiles import get_profile_by_user_id
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


def _membership_admin_read(membership, user: User, profile: Profile, program) -> ProgramMembershipAdminRead:
    return ProgramMembershipAdminRead(
        id=membership.id,
        user_id=membership.user_id,
        status=membership.status,
        verified_at=membership.verified_at,
        revoked_at=membership.revoked_at,
        created_at=membership.created_at,
        updated_at=membership.updated_at,
        program_slug=program.slug,
        program_name=program.name,
        user_email=user.email,
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


@router.get('/campus-positions', response_model=list[CampusPositionAdminRead])
async def list_campus_positions(
    status: str = 'pending',
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[CampusPositionAdminRead]:
    """List positions by status (pending | verified | rejected | revoked) — lets the admin act on
    verified positions (e.g. revoke) without pasting a UUID."""
    rows = await campus_admin.list_positions(db, status=status)
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
    payload: PositionRevokeRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionRead:
    position = await campus_admin.revoke_position(
        db,
        actor=actor,
        position_id=position_id,
        review_note=payload.review_note,
        archive_posts=payload.archive_posts,
    )
    return CampusPositionRead.model_validate(position)


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
    if publishing.should_push_on_publish(post):
        background_tasks.add_task(publishing.push_published_post, post.id)
    return CampusPostAdminRead.model_validate(post)


@router.post('/campus-posts/{post_id}/archive', response_model=CampusPostAdminRead)
async def archive_campus_post(
    post_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> CampusPostAdminRead:
    post = await posts_admin.archive_post(db, actor=actor, post_id=post_id)
    return CampusPostAdminRead.model_validate(post)


@router.delete('/campus-posts/{post_id}')
async def delete_campus_post(
    post_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    await posts_admin.delete_post(db, actor=actor, post_id=post_id)
    return {'status': 'deleted', 'post_id': str(post_id)}


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


@router.delete('/campus-resources/{resource_id}')
async def delete_campus_resource(
    resource_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    await resources_admin.delete_resource(db, actor=actor, resource_id=resource_id)
    return {'status': 'deleted', 'resource_id': str(resource_id)}


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


@router.get('/programs/{slug}/members', response_model=list[ProgramMembershipAdminRead])
async def list_program_memberships(
    slug: str,
    status: str = 'active',
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[ProgramMembershipAdminRead]:
    program = await programs_admin.get_program_by_slug_or_404(db, slug)
    rows = await programs_admin.list_memberships(db, program_id=program.id, status_filter=status)
    return [_membership_admin_read(membership, user, profile, program) for membership, user, profile in rows]


@router.post('/programs/{slug}/members', response_model=ProgramMembershipAdminRead, status_code=201)
async def verify_program_membership(
    slug: str,
    payload: ProgramMembershipVerifyRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> ProgramMembershipAdminRead:
    program = await programs_admin.get_program_by_slug_or_404(db, slug)
    membership, user, profile = await programs_admin.verify_membership(
        db, actor=actor, program=program, email=payload.email
    )

    from app.features.realtime.runtime import emit_notification

    await emit_notification(user_id=user.id, notif_type='program_membership_verified')
    return _membership_admin_read(membership, user, profile, program)


@router.post('/programs/{slug}/members/{user_id}/revoke', response_model=ProgramMembershipAdminRead)
async def revoke_program_membership(
    slug: str,
    user_id: UUID,
    payload: ProgramMembershipRevokeRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> ProgramMembershipAdminRead:
    program = await programs_admin.get_program_by_slug_or_404(db, slug)
    membership = await programs_admin.revoke_membership(
        db, actor=actor, program=program, user_id=user_id, reason=payload.reason
    )
    target = await db.get(User, membership.user_id)
    profile = await get_profile_by_user_id(db, membership.user_id)
    return _membership_admin_read(membership, target, profile, program)
