from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user, get_supabase_claims
from app.features.auth import email_hook
from app.features.auth.schema import BootstrapResponse, CurrentUserResponse, ForgotPasswordRequest, MessageResponse
from app.features.auth.service import bootstrap_user
from app.models import User
from app.security import SupabaseClaims
from app.shared.rate_limit import forgot_password_email_limit, forgot_password_ip_limit
from app.shared.supabase_admin import request_password_reset

router = APIRouter(prefix='/auth', tags=['auth'])


@router.post('/webhooks/send-email')
async def send_email_hook(request: Request) -> JSONResponse:
    """Supabase 'Send Email' Auth Hook — see `app/features/auth/email_hook.py` for the full
    picture. Signature-verification failures (401/503) use FastAPI's normal error shape; a
    same-request failure to actually send the email uses Supabase's documented hook-error shape
    so the failure blocks the underlying auth action instead of completing silently with no way
    for the user to confirm."""
    payload = await email_hook.verify_and_parse(request)
    try:
        email_hook.send_for_payload(payload)
    except HTTPException as exc:
        return JSONResponse(status_code=exc.status_code, content={'error': {'http_code': exc.status_code, 'message': exc.detail}})
    return JSONResponse(content={})


@router.post(
    '/forgot-password',
    response_model=MessageResponse,
    dependencies=[Depends(forgot_password_ip_limit)],
)
async def forgot_password(payload: ForgotPasswordRequest) -> MessageResponse:
    """Public, unauthenticated — and deliberately reports the same success message whether or not
    an account exists for this email, so this can never be used to enumerate accounts.

    Rate-limited twice over: per caller IP, and per target address. The IP cap alone still lets a
    distributed caller bomb one person's inbox, so both are needed."""
    # Also cap per target address: an IP cap alone still allows a distributed caller to bomb one
    # person's inbox. Checked before any send so a bombing attempt costs no email quota.
    forgot_password_email_limit.check(payload.email)
    portal_url = settings.admin_portal_url if payload.portal == 'admin' else settings.employer_portal_url
    redirect_to = f'{portal_url}/reset-password' if portal_url else None
    request_password_reset(payload.email, redirect_to=redirect_to)
    return MessageResponse(message='If an account exists for that email, a reset link has been sent.')


@router.post('/bootstrap', response_model=BootstrapResponse)
async def bootstrap(
    claims: SupabaseClaims = Depends(get_supabase_claims),
    db: AsyncSession = Depends(get_db),
) -> BootstrapResponse:
    user = await bootstrap_user(db, claims)
    profile_completed = bool(user.profile and user.profile.profile_completed)
    assert user.auth_user_id is not None
    return BootstrapResponse(
        id=user.id,
        email=user.email,
        role=user.role,
        status=user.status,
        is_verified=user.is_verified,
        profile_completed=profile_completed,
        auth_user_id=user.auth_user_id,
    )


@router.get('/me', response_model=CurrentUserResponse)
async def me(current_user: User = Depends(get_current_user)) -> CurrentUserResponse:
    profile_completed = bool(current_user.profile and current_user.profile.profile_completed)
    return CurrentUserResponse(
        id=current_user.id,
        email=current_user.email,
        role=current_user.role,
        status=current_user.status,
        is_verified=current_user.is_verified,
        profile_completed=profile_completed,
        auth_user_id=current_user.auth_user_id,
    )
