from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.features.employers import service
from app.features.employers.auth import EmployerAuthContext, require_approved_employer
from app.features.employers.rate_limit import opportunity_submit_limit
from app.features.employers.schema import (
    EmployerOrganizationRead,
    EmployerRegisterRequest,
    OpportunitySubmissionCreate,
    OpportunitySubmissionRead,
)

router = APIRouter(prefix='/employers', tags=['employers'])


@router.post('/register', response_model=EmployerOrganizationRead, status_code=201)
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
