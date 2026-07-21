from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user, get_supabase_claims
from app.features.auth.schema import BootstrapResponse, CurrentUserResponse
from app.features.auth.service import bootstrap_user
from app.models import User
from app.security import SupabaseClaims

router = APIRouter(prefix='/auth', tags=['auth'])


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
