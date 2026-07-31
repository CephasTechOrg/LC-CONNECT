from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.features.programs import service
from app.features.programs.schema import ProgramMembershipRead
from app.models import User

router = APIRouter(prefix='/programs', tags=['programs'])


@router.get('/me', response_model=list[ProgramMembershipRead])
async def get_my_program_memberships(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ProgramMembershipRead]:
    rows = await service.list_active_memberships(db, current_user.id)
    return [
        ProgramMembershipRead(
            id=membership.id,
            user_id=membership.user_id,
            status=membership.status,
            verified_at=membership.verified_at,
            revoked_at=membership.revoked_at,
            created_at=membership.created_at,
            updated_at=membership.updated_at,
            program_slug=program.slug,
            program_name=program.name,
        )
        for membership, program in rows
    ]
