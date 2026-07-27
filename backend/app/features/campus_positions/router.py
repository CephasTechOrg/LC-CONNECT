from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user, require_verified_student
from app.features.campus_positions import service
from app.features.campus_positions.schema import (
    CampusPositionCreate,
    CampusPositionRead,
    CampusPositionUpdate,
)
from app.models import User
from app.shared.profiles import get_profile_by_user_id

router = APIRouter(prefix='/campus-positions', tags=['campus-positions'])


@router.get('/me', response_model=CampusPositionRead)
async def get_my_campus_position(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionRead:
    position = await service.get_primary_position(db, current_user.id)
    if position is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No campus position on file')
    return CampusPositionRead.model_validate(position)


@router.post('/me', response_model=CampusPositionRead, status_code=status.HTTP_201_CREATED)
async def create_my_campus_position(
    payload: CampusPositionCreate,
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionRead:
    if current_user.role not in {'staff', 'admin', 'student'}:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Campus positions are not available for this account')
    profile = await get_profile_by_user_id(db, current_user.id)
    position = await service.upsert_primary_position(db, current_user, profile, payload)
    return CampusPositionRead.model_validate(position)


@router.patch('/me', response_model=CampusPositionRead)
async def update_my_campus_position(
    payload: CampusPositionUpdate,
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
) -> CampusPositionRead:
    profile = await get_profile_by_user_id(db, current_user.id)
    position = await service.update_primary_position(db, current_user, profile, payload)
    return CampusPositionRead.model_validate(position)
