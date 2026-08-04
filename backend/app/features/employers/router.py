from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.features.employers import discovery, service
from app.features.employers.auth import EmployerAuthContext, require_approved_employer
from app.features.employers.rate_limit import opportunity_submit_limit
from app.features.employers.schema import (
    EmployerOrganizationRead,
    EmployerRegisterRequest,
    EmployerScholarView,
    MyEmployerRead,
    OpportunitySubmissionCreate,
    OpportunitySubmissionRead,
)
from app.features.scholars.schema import SignedUrlRead
from app.shared.rate_limit import employer_register_limit
from app.shared.storage import storage_service

router = APIRouter(prefix='/employers', tags=['employers'])


def _scholar_view(profile, social_profile, *, headshot_url: str | None = None) -> EmployerScholarView:
    return EmployerScholarView(
        user_id=profile.user_id,
        display_name=social_profile.display_name,
        linkedin_url=profile.linkedin_url,
        handshake_url=profile.handshake_url,
        summary=profile.summary,
        skills=profile.skills,
        career_interests=profile.career_interests,
        has_headshot=profile.headshot_path is not None,
        has_resume=profile.resume_path is not None,
        headshot_url=headshot_url,
    )


@router.post(
    '/register',
    response_model=EmployerOrganizationRead,
    status_code=201,
    dependencies=[Depends(employer_register_limit)],
)
async def register_employer(
    payload: EmployerRegisterRequest,
    db: AsyncSession = Depends(get_db),
) -> EmployerOrganizationRead:
    """Public, unauthenticated — a prospective employer has no account yet. Leaves them `pending`
    with zero access until an Honors Admin approves."""
    org = await service.register_employer(
        db,
        organization_name=payload.organization_name,
        contact_name=payload.contact_name,
        contact_email=payload.contact_email,
    )
    return EmployerOrganizationRead.model_validate(org)


@router.get('/me', response_model=MyEmployerRead)
async def get_my_employer_context(
    ctx: EmployerAuthContext = Depends(require_approved_employer),
) -> MyEmployerRead:
    """The portal's session-check call — succeeding at all means the caller is an *approved*
    employer (pending/rejected 403s with the matching message before this ever returns)."""
    return MyEmployerRead(
        organization_id=ctx.organization.id,
        organization_name=ctx.organization.name,
        organization_status=ctx.organization.status,
        email=ctx.account.email,
        display_name=ctx.account.display_name,
    )


@router.post(
    '/opportunities',
    response_model=OpportunitySubmissionRead,
    status_code=201,
    dependencies=[Depends(opportunity_submit_limit)],
)
async def submit_opportunity(
    payload: OpportunitySubmissionCreate,
    ctx: EmployerAuthContext = Depends(require_approved_employer),
    db: AsyncSession = Depends(get_db),
) -> OpportunitySubmissionRead:
    submission = await service.submit_opportunity(db, account=ctx.account, payload=payload)
    return OpportunitySubmissionRead.model_validate(submission)


@router.get('/opportunities/me', response_model=list[OpportunitySubmissionRead])
async def list_my_opportunities(
    ctx: EmployerAuthContext = Depends(require_approved_employer),
    db: AsyncSession = Depends(get_db),
) -> list[OpportunitySubmissionRead]:
    rows = await service.list_my_submissions(db, organization_id=ctx.organization.id)
    return [OpportunitySubmissionRead.model_validate(s) for s in rows]


@router.get('/scholars', response_model=list[EmployerScholarView])
async def list_eligible_scholars(
    _: EmployerAuthContext = Depends(require_approved_employer),
    db: AsyncSession = Depends(get_db),
) -> list[EmployerScholarView]:
    """Only scholars with active Presidential Scholars membership **and** current
    employer-visibility consent — re-evaluated on every call, never cached."""
    rows = await discovery.list_eligible_scholars(db)
    # Sign every headshot in ONE call so the directory can show faces without N round trips.
    signed = storage_service.scholar_signed_urls(
        [p.headshot_path for p, _ in rows if p.headshot_path],
        expires_in=settings.scholar_signed_url_expires_seconds,
    )
    return [
        _scholar_view(profile, social_profile, headshot_url=signed.get(profile.headshot_path or ''))
        for profile, social_profile in rows
    ]


@router.get('/scholars/{user_id}', response_model=EmployerScholarView)
async def get_eligible_scholar(
    user_id: UUID,
    ctx: EmployerAuthContext = Depends(require_approved_employer),
    db: AsyncSession = Depends(get_db),
) -> EmployerScholarView:
    profile, social_profile = await discovery.get_eligible_scholar_or_404(db, user_id)
    await discovery.record_view(db, employer_account_id=ctx.account.id, scholar_user_id=user_id)
    # Signed inline so the profile renders the face immediately — best-effort, since a signing
    # hiccup should degrade to initials, never 500 a profile the employer is allowed to see.
    headshot_url = None
    if profile.headshot_path:
        signed = storage_service.scholar_signed_urls(
            [profile.headshot_path], expires_in=settings.scholar_signed_url_expires_seconds
        )
        headshot_url = signed.get(profile.headshot_path)
    return _scholar_view(profile, social_profile, headshot_url=headshot_url)


@router.get('/scholars/{user_id}/headshot-url', response_model=SignedUrlRead)
async def get_scholar_headshot_url(
    user_id: UUID,
    _: EmployerAuthContext = Depends(require_approved_employer),
    db: AsyncSession = Depends(get_db),
) -> SignedUrlRead:
    url = await discovery.headshot_signed_url(db, user_id)
    return SignedUrlRead(url=url, expires_in=settings.scholar_signed_url_expires_seconds)


@router.get('/scholars/{user_id}/resume-url', response_model=SignedUrlRead)
async def get_scholar_resume_url(
    user_id: UUID,
    _: EmployerAuthContext = Depends(require_approved_employer),
    db: AsyncSession = Depends(get_db),
) -> SignedUrlRead:
    url = await discovery.resume_signed_url(db, user_id)
    return SignedUrlRead(url=url, expires_in=settings.scholar_signed_url_expires_seconds)
