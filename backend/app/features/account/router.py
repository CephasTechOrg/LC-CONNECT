from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.features.account import service
from app.features.account.schema import AccountDeleteRequest, AccountDeleteResponse
from app.models import User

router = APIRouter(prefix='/account', tags=['account'])


@router.delete('', response_model=AccountDeleteResponse)
async def delete_account(
    payload: AccountDeleteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete the caller's account. Irreversible. `confirm_email` must match the
    caller's own email. The account is anonymized in place — see the service for what is kept."""
    if payload.confirm_email.strip().lower() != current_user.email.lower():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Confirmation email does not match your account')
    await service.delete_account(db, current_user)
    return AccountDeleteResponse()
