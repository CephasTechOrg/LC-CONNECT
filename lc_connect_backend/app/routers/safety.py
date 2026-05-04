from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models import Block, Report, User
from app.schemas import ReportCreate, ReportRead

router = APIRouter(tags=['safety'])


@router.post('/blocks/{user_id}', status_code=status.HTTP_201_CREATED)
async def block_user(user_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    if user_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='You cannot block yourself')
    target = await db.get(User, user_id)
    if target is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    existing = (await db.execute(select(Block).where(Block.blocker_id == current_user.id, Block.blocked_id == user_id))).scalar_one_or_none()
    if existing is None:
        db.add(Block(blocker_id=current_user.id, blocked_id=user_id))
        await db.commit()
    return {'status': 'blocked'}


@router.delete('/blocks/{user_id}')
async def unblock_user(user_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    existing = (await db.execute(select(Block).where(Block.blocker_id == current_user.id, Block.blocked_id == user_id))).scalar_one_or_none()
    if existing is not None:
        await db.delete(existing)
        await db.commit()
    return {'status': 'unblocked'}


@router.post('/reports', response_model=ReportRead, status_code=status.HTTP_201_CREATED)
async def create_report(payload: ReportCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    report = Report(
        reporter_id=current_user.id,
        reported_user_id=payload.reported_user_id,
        activity_id=payload.activity_id,
        reason=payload.reason.strip(),
        details=payload.details,
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)
    return report
