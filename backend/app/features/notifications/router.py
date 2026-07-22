from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_verified_student
from app.features.notifications.schema import DeviceRegister
from app.features.notifications.service import register_device, unregister_device
from app.models import User

router = APIRouter(prefix='/devices', tags=['notifications'])


@router.post('', status_code=status.HTTP_204_NO_CONTENT)
async def register(
    payload: DeviceRegister,
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
) -> None:
    await register_device(db, current_user.id, payload.token, payload.platform)


@router.delete('/{token}', status_code=status.HTTP_204_NO_CONTENT)
async def unregister(
    token: str,
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
) -> None:
    await unregister_device(db, token)
