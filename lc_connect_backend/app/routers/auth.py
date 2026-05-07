import hashlib
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.email import send_reset_otp
from app.models import Profile, User
from app.schemas import (
    CurrentUserResponse,
    ForgotPasswordRequest,
    LoginRequest,
    MessageResponse,
    RegisterRequest,
    ResetPasswordRequest,
    TokenResponse,
)
from app.security import create_access_token, hash_password, verify_password

router = APIRouter(prefix='/auth', tags=['auth'])


@router.post('/register', response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    email = payload.email.lower().strip()
    existing = await db.execute(select(User).where(User.email == email))
    if existing.scalar_one_or_none() is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Email already registered')

    user = User(email=email, password_hash=hash_password(payload.password))
    db.add(user)
    await db.flush()
    display_name = payload.display_name.strip() if payload.display_name else email.split('@')[0]
    db.add(Profile(user_id=user.id, display_name=display_name))
    await db.commit()

    return TokenResponse(access_token=create_access_token(user.id))


@router.post('/login', response_model=TokenResponse)
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db)) -> TokenResponse:
    email = payload.email.lower().strip()
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid email or password')
    if not user.is_active or user.status != 'active':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Account is inactive or suspended')
    return TokenResponse(access_token=create_access_token(user.id))


@router.get('/me', response_model=CurrentUserResponse)
async def me(current_user: User = Depends(get_current_user)) -> CurrentUserResponse:
    return CurrentUserResponse(
        id=current_user.id,
        email=current_user.email,
        role=current_user.role,
        status=current_user.status,
        is_verified=current_user.is_verified,
    )


@router.post('/forgot-password', response_model=MessageResponse)
async def forgot_password(
    payload: ForgotPasswordRequest,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
) -> MessageResponse:
    email = payload.email.lower().strip()
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()

    # Always return the same message — prevents email enumeration
    response = MessageResponse(message='If that email is registered, a reset code has been sent.')

    if user is None:
        return response

    otp = str(secrets.randbelow(900000) + 100000)  # 6-digit code, never starts with 0
    user.reset_otp_hash = hashlib.sha256(otp.encode()).hexdigest()
    user.reset_otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=15)
    await db.commit()

    background_tasks.add_task(send_reset_otp, user.email, otp)
    return response


@router.post('/reset-password', response_model=MessageResponse)
async def reset_password(
    payload: ResetPasswordRequest,
    db: AsyncSession = Depends(get_db),
) -> MessageResponse:
    email = payload.email.lower().strip()
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()

    invalid = HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid or expired reset code')

    if user is None or not user.reset_otp_hash or not user.reset_otp_expires_at:
        raise invalid

    if datetime.now(timezone.utc) > user.reset_otp_expires_at:
        raise invalid

    submitted_hash = hashlib.sha256(payload.otp.encode()).hexdigest()
    if not secrets.compare_digest(submitted_hash, user.reset_otp_hash):
        raise invalid

    user.password_hash = hash_password(payload.new_password)
    user.reset_otp_hash = None
    user.reset_otp_expires_at = None
    await db.commit()

    return MessageResponse(message='Password reset successfully. You can now log in.')
