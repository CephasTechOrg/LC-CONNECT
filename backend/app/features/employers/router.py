from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.features.employers import service
from app.features.employers.schema import EmployerOrganizationRead, EmployerRegisterRequest

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
