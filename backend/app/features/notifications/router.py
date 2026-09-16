from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_email_confirmed_user
from app.features.notifications.schema import DeviceRegister, NotificationRead, UnreadCount
from app.features.notifications.service import (
    list_notifications,
    mark_all_read,
    mark_one_read,
    register_device,
    unread_count,
    unregister_device,
)
from app.models import User

router = APIRouter(prefix='/devices', tags=['notifications'])

# In-app notification inbox (distinct from the push device-token endpoints above).
inbox_router = APIRouter(prefix='/notifications', tags=['notifications'])


@inbox_router.get('', response_model=list[NotificationRead])
async def list_my_notifications(
    limit: int = Query(default=50, ge=1, le=100),
    current_user: User = Depends(require_email_confirmed_user),
    db: AsyncSession = Depends(get_db),
):
    return await list_notifications(db, current_user.id, limit=limit)


@inbox_router.get('/unread-count', response_model=UnreadCount)
async def get_unread_count(
    current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)
):
    return UnreadCount(count=await unread_count(db, current_user.id))


@inbox_router.post('/read', status_code=status.HTTP_204_NO_CONTENT)
async def mark_notifications_read(
    current_user: User = Depends(require_email_confirmed_user), db: AsyncSession = Depends(get_db)
):
    """Mark every notification read — the explicit "Mark all read" action.

    This used to be called automatically when the inbox mounted, which destroyed the unread state
    before the user could see which rows were new. The client now marks rows individually as they
    are opened (see below) and only calls this on a deliberate action.
    """
    await mark_all_read(db, current_user.id)


@inbox_router.post('/{notification_id}/read', status_code=status.HTTP_204_NO_CONTENT)
async def mark_notification_read(
    notification_id: UUID,
    current_user: User = Depends(require_email_confirmed_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Mark one notification read — called when the user opens it.

    Deliberately 204 whether or not a row changed: an unknown id and an already-read notification
    are both "nothing left to do", and distinguishing them would tell a caller whether a given
    notification id exists for another user.
    """
    await mark_one_read(db, current_user.id, notification_id)


@router.post('', status_code=status.HTTP_204_NO_CONTENT)
async def register(
    payload: DeviceRegister,
    current_user: User = Depends(require_email_confirmed_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    await register_device(db, current_user.id, payload.token, payload.platform)


@router.delete('/{token}', status_code=status.HTTP_204_NO_CONTENT)
async def unregister(
    token: str,
    current_user: User = Depends(require_email_confirmed_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    await unregister_device(db, current_user.id, token)
