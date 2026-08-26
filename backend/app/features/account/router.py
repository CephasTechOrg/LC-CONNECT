from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.features.account import service
from app.features.account.schema import AccountDeleteRequest, AccountDeleteResponse
from app.models import User
from app.shared import supabase_admin
from app.shared.rate_limit import RateLimiter

router = APIRouter(prefix='/account', tags=['account'])

# Bound password-guessing on the delete endpoint (authenticated, but still abusable).
_delete_password_limiter = RateLimiter(5, 900, name='account_delete')  # 5 / 15 min / user


@router.delete('', response_model=AccountDeleteResponse)
async def delete_account(
    payload: AccountDeleteRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Permanently delete the caller's account. Irreversible.

    Requires (1) email confirmation matching the account and (2) the current password
    verified against Supabase Auth. A valid access token alone is not enough.
    """
    if payload.confirm_email.strip().lower() != current_user.email.lower():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Confirmation email does not match your account',
        )

    if not await _delete_password_limiter.aallow(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail='Too many deletion attempts. Please wait and try again.',
        )

    expected_sub = str(current_user.auth_user_id) if current_user.auth_user_id else None
    if not supabase_admin.verify_password_for_email(
        current_user.email,
        payload.password,
        expected_auth_user_id=expected_sub,
    ):
        # 403 — not 401. Mobile Dio treats 401 as session death and signs the user out.
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Incorrect password',
        )

    await service.delete_account(db, current_user)
    return AccountDeleteResponse()
