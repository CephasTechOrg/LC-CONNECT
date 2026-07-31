from uuid import UUID

from fastapi import APIRouter, BackgroundTasks, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_admin_aal2
from app.features.admin import admins as admins_admin
from app.features.admin import campus_positions as campus_admin
from app.features.admin import campus_posts as posts_admin
from app.features.admin import campus_resources as resources_admin
from app.features.admin import dashboard as dashboard_admin
from app.features.admin import employers as employers_admin
from app.features.admin import programs as programs_admin
from app.features.admin import system_status as system_status_admin
from app.features.admin.schema import (
    AdminDashboardSummary,
    AdminMembershipRead,
    AdminUserRead,
    CampusPositionAdminRead,
    CampusPostAdminRead,
    CampusResourceAdminRead,
    EmployerOrganizationAdminRead,
    EmployerRejectRequest,
    InviteAdminRequest,
    MyAdminScopesRead,
    OpportunitySubmissionAdminRead,
    OpportunitySubmissionRejectRequest,
    PositionReviewRequest,
    PositionRevokeRequest,
    ProgramMembershipAdminRead,
    ProgramMembershipRevokeRequest,
    ProgramMembershipVerifyRequest,
    SuspendUserRequest,
    SystemStatusRead,
)
from app.features.admin.service import reactivate_user as do_reactivate_user
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
from app.features.employers.schema import EmployerOrganizationRead, OpportunitySubmissionRead
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


@router.get('/dashboard/summary', response_model=AdminDashboardSummary)
async def get_dashboard_summary(
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> AdminDashboardSummary:
    return await dashboard_admin.get_dashboard_summary(db, user_id=actor.id)


@router.get('/system-status', response_model=SystemStatusRead)
async def get_system_status(
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> SystemStatusRead:
    return await system_status_admin.get_system_status(db)


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


@router.post('/users/{user_id}/reactivate')
async def reactivate_user(
    user_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
):
    user = await do_reactivate_user(db, user_id, actor_id=actor.id)
    return {'status': 'active', 'user_id': str(user.id)}


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
    _: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> list[ProgramMembershipAdminRead]:
    program = await programs_admin.get_program_by_slug_or_404(db, slug)
    rows = await programs_admin.list_memberships(db, program_id=program.id, status_filter=status)
    return [_membership_admin_read(membership, user, profile, program) for membership, user, profile in rows]


@router.post('/programs/{slug}/members', response_model=ProgramMembershipAdminRead, status_code=201)
async def verify_program_membership(
    slug: str,
    payload: ProgramMembershipVerifyRequest,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
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
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> ProgramMembershipAdminRead:
    program = await programs_admin.get_program_by_slug_or_404(db, slug)
    membership = await programs_admin.revoke_membership(
        db, actor=actor, program=program, user_id=user_id, reason=payload.reason
    )
    target = await db.get(User, membership.user_id)
    profile = await get_profile_by_user_id(db, membership.user_id)
    return _membership_admin_read(membership, target, profile, program)


def _admin_membership_read(membership, user: User, profile: Profile) -> AdminMembershipRead:
    return AdminMembershipRead(
        id=membership.id,
        user_id=membership.user_id,
        role=membership.role,
        status=membership.status,
        invited_at=membership.invited_at,
        revoked_at=membership.revoked_at,
        user_email=user.email,
        display_name=profile.display_name,
    )


@router.get('/admins/me/scopes', response_model=MyAdminScopesRead)
async def get_my_admin_scopes(
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> MyAdminScopesRead:
    """Lets the admin portal gate its own nav — any admin can see their own scopes."""
    scopes = await admins_admin.get_admin_scopes(db, actor.id)
    return MyAdminScopesRead(scopes=sorted(scopes))


@router.get('/admins', response_model=list[AdminMembershipRead])
async def list_admin_memberships(
    _: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> list[AdminMembershipRead]:
    """The admin roster — read-only, open to any admin (no scope beyond `require_admin_aal2`)."""
    rows = await admins_admin.list_memberships(db)
    return [_admin_membership_read(membership, user, profile) for membership, user, profile in rows]


@router.post('/admins/invite', response_model=AdminMembershipRead, status_code=201)
async def invite_admin(
    payload: InviteAdminRequest,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> AdminMembershipRead:
    """Only Super Admin / School Admin can actually succeed here — `invite_admin` enforces the
    invite matrix itself (403 for anyone else), `require_admin_aal2` is just the base gate."""
    membership, user, profile = await admins_admin.invite_admin(
        db, actor=actor, email=payload.email, role=payload.role
    )
    return _admin_membership_read(membership, user, profile)


@router.post('/admins/{membership_id}/revoke', response_model=AdminMembershipRead)
async def revoke_admin(
    membership_id: UUID,
    actor: User = Depends(require_admin_aal2),
    db: AsyncSession = Depends(get_db),
) -> AdminMembershipRead:
    membership = await admins_admin.revoke_admin_membership(db, actor=actor, membership_id=membership_id)
    user = await db.get(User, membership.user_id)
    profile = await get_profile_by_user_id(db, membership.user_id)
    return _admin_membership_read(membership, user, profile)


def _employer_org_admin_read(org, account) -> EmployerOrganizationAdminRead:
    base = EmployerOrganizationRead.model_validate(org).model_dump()
    return EmployerOrganizationAdminRead(
        **base,
        contact_email=account.email,
        contact_name=account.display_name,
        review_note=org.review_note,
    )


@router.get('/employers', response_model=list[EmployerOrganizationAdminRead])
async def list_employer_organizations(
    status: str = 'pending',
    _: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> list[EmployerOrganizationAdminRead]:
    rows = await employers_admin.list_organizations(db, status_filter=status)
    return [_employer_org_admin_read(org, account) for org, account in rows]


@router.post('/employers/{org_id}/approve', response_model=EmployerOrganizationAdminRead)
async def approve_employer_organization(
    org_id: UUID,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> EmployerOrganizationAdminRead:
    org, account = await employers_admin.approve_organization(db, actor=actor, org_id=org_id)
    return _employer_org_admin_read(org, account)


@router.post('/employers/{org_id}/reject', response_model=EmployerOrganizationAdminRead)
async def reject_employer_organization(
    org_id: UUID,
    payload: EmployerRejectRequest,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> EmployerOrganizationAdminRead:
    org = await employers_admin.reject_organization(db, actor=actor, org_id=org_id, reason=payload.reason)
    account = await employers_admin.get_account_for_org(db, org.id)
    return _employer_org_admin_read(org, account)


def _submission_admin_read(submission, *, org_name: str) -> OpportunitySubmissionAdminRead:
    base = OpportunitySubmissionRead.model_validate(submission).model_dump()
    return OpportunitySubmissionAdminRead(**base, organization_id=submission.organization_id, organization_name=org_name)


@router.get('/employers/opportunities', response_model=list[OpportunitySubmissionAdminRead])
async def list_opportunity_submissions(
    status: str = 'pending',
    _: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> list[OpportunitySubmissionAdminRead]:
    rows = await employers_admin.list_submissions(db, status_filter=status)
    return [_submission_admin_read(submission, org_name=org.name) for submission, org in rows]


@router.post('/employers/opportunities/{submission_id}/approve', response_model=OpportunitySubmissionAdminRead)
async def approve_opportunity_submission(
    submission_id: UUID,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> OpportunitySubmissionAdminRead:
    submission = await employers_admin.approve_submission(db, actor=actor, submission_id=submission_id)
    org = await employers_admin.get_organization_or_404(db, submission.organization_id)
    return _submission_admin_read(submission, org_name=org.name)


@router.post('/employers/opportunities/{submission_id}/reject', response_model=OpportunitySubmissionAdminRead)
async def reject_opportunity_submission(
    submission_id: UUID,
    payload: OpportunitySubmissionRejectRequest,
    actor: User = Depends(admins_admin.require_admin_scope('honors_admin')),
    db: AsyncSession = Depends(get_db),
) -> OpportunitySubmissionAdminRead:
    submission = await employers_admin.reject_submission(
        db, actor=actor, submission_id=submission_id, reason=payload.reason
    )
    org = await employers_admin.get_organization_or_404(db, submission.organization_id)
    return _submission_admin_read(submission, org_name=org.name)
