from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.features.safety.schema import ReportCreate
from app.features.safety.service import add_block, remove_block
from app.features.safety.service import create_report as persist_report
from app.models import User
from app.shared.schemas import ReportRead

router = APIRouter(tags=['safety'])


@router.post('/blocks/{user_id}', status_code=status.HTTP_201_CREATED)
async def block_user(user_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if user_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='You cannot block yourself')
    target = await db.get(User, user_id)
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    await add_block(db, current_user.id, user_id)
    return {'status': 'blocked'}


@router.delete('/blocks/{user_id}')
async def unblock_user(user_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await remove_block(db, current_user.id, user_id)
    return {'status': 'unblocked'}


@router.post('/reports', response_model=ReportRead, status_code=status.HTTP_201_CREATED)
async def create_report(payload: ReportCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await persist_report(db, current_user.id, payload)
