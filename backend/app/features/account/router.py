from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user, require_email_confirmed_user, require_suspended_user
from app.features.account import export as account_export
from app.features.account import service
from app.features.account import suspension as suspension_service
from app.features.account.schema import (
    AccountDeleteRequest,
    AccountDeleteResponse,
    AccountExportResponse,
    SuspensionAppealCreate,
    SuspensionAppealSubmitResponse,
    SuspensionStatusResponse,
    SuspensionAppealRead,
)
from app.models import User
from app.shared import supabase_admin
from app.shared.rate_limit import RateLimiter

router = APIRouter(prefix='/account', tags=['account'])

# Bound password-guessing on the delete endpoint (authenticated, but still abusable).
_delete_password_limiter = RateLimiter(5, 900, name='account_delete')  # 5 / 15 min / user
# Export is heavier than a normal GET — keep abuse off shared DB.
_export_limiter = RateLimiter(5, 86_400, name='account_export')  # 5 / day / user
_appeal_limiter = RateLimiter(3, 86_400, name='suspension_appeal')  # 3 / day / user


@router.get('/suspension-status', response_model=SuspensionStatusResponse)
async def suspension_status(
    current_user: User = Depends(require_suspended_user),
    db: AsyncSession = Depends(get_db),
):
    """Suspended users can poll appeal state without full app access."""
    open_appeal = await suspension_service.get_open_appeal(db, current_user.id)
    return SuspensionStatusResponse(
        support_email=suspension_service.support_contact_email(),
        open_appeal=SuspensionAppealRead.model_validate(open_appeal) if open_appeal else None,
    )


@router.post('/suspension-appeal', response_model=SuspensionAppealSubmitResponse, status_code=status.HTTP_201_CREATED)
async def submit_suspension_appeal(
    payload: SuspensionAppealCreate,
    current_user: User = Depends(require_suspended_user),
    db: AsyncSession = Depends(get_db),
):
    """File a one-time open appeal while suspended. Does not auto-reactivate the account."""
    if not await _appeal_limiter.aallow(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail='Too many appeal submissions today. Please try again tomorrow.',
        )
    appeal = await suspension_service.submit_appeal(db, current_user, message=payload.message)
    return SuspensionAppealSubmitResponse(appeal=SuspensionAppealRead.model_validate(appeal))


@router.get('/export', response_model=AccountExportResponse)
async def export_account(
    current_user: User = Depends(require_email_confirmed_user),
    db: AsyncSession = Depends(get_db),
):
    """Download a JSON copy of the caller's own data (profile, messages sent, social graph, …)."""
    if not await _export_limiter.aallow(current_user.id):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail='Too many export requests today. Please try again tomorrow.',
        )
    payload = await account_export.build_account_export(db, current_user)
    # Attachment header helps browsers/desktop clients save the file; mobile still reads JSON body.
    return JSONResponse(
        content=AccountExportResponse.model_validate(payload).model_dump(mode='json'),
        headers={
            'Content-Disposition': f'attachment; filename="lc-connect-export-{current_user.id}.json"',
        },
    )


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
