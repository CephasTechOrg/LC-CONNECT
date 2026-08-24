from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_email_confirmed_user
from app.features.scholars import service
from app.features.scholars.schema import (
    ConsentUpdateRequest,
    ScholarProfessionalProfileRead,
    ScholarProfessionalProfileUpdate,
    SignedUrlRead,
)
from app.models import User
from app.shared.rate_limit import scholar_upload_limit

router = APIRouter(prefix='/scholars', tags=['scholars'])


async def require_verified_scholar(
    current_user: User = Depends(require_email_confirmed_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Blueprint Bond is verified-scholar-only — a normal student gets a 403, not just a
    hidden button (the app never relies on UI-only hiding for this)."""
    if not await service.is_verified_scholar(db, current_user.id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='This feature is only available to verified Presidential Scholars',
        )
    return current_user


@router.get('/me', response_model=ScholarProfessionalProfileRead)
async def get_my_scholar_profile(
    current_user: User = Depends(require_verified_scholar),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfessionalProfileRead:
    return await service.get_my_profile(db, current_user.id)


@router.patch('/me', response_model=ScholarProfessionalProfileRead)
async def update_my_scholar_profile(
    payload: ScholarProfessionalProfileUpdate,
    current_user: User = Depends(require_verified_scholar),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfessionalProfileRead:
    return await service.update_profile(db, current_user.id, payload)


@router.post('/me/consent', response_model=ScholarProfessionalProfileRead)
async def set_my_employer_consent(
    payload: ConsentUpdateRequest,
    current_user: User = Depends(require_verified_scholar),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfessionalProfileRead:
    return await service.set_consent(db, current_user.id, payload.consent)


@router.post(
    '/me/headshot',
    response_model=ScholarProfessionalProfileRead,
    dependencies=[Depends(scholar_upload_limit)],
)
async def upload_my_headshot(
    file: UploadFile = File(...),
    current_user: User = Depends(require_verified_scholar),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfessionalProfileRead:
    data = await file.read()
    return await service.upload_headshot(db, current_user.id, data)


@router.post(
    '/me/resume',
    response_model=ScholarProfessionalProfileRead,
    dependencies=[Depends(scholar_upload_limit)],
)
async def upload_my_resume(
    file: UploadFile = File(...),
    current_user: User = Depends(require_verified_scholar),
    db: AsyncSession = Depends(get_db),
) -> ScholarProfessionalProfileRead:
    data = await file.read()
    return await service.upload_resume(db, current_user.id, data)


@router.get('/me/headshot-url', response_model=SignedUrlRead)
async def get_my_headshot_url(
    current_user: User = Depends(require_verified_scholar),
    db: AsyncSession = Depends(get_db),
) -> SignedUrlRead:
    url = await service.headshot_signed_url(db, current_user.id)
    return SignedUrlRead(url=url, expires_in=settings.scholar_signed_url_expires_seconds)


@router.get('/me/resume-url', response_model=SignedUrlRead)
async def get_my_resume_url(
    current_user: User = Depends(require_verified_scholar),
    db: AsyncSession = Depends(get_db),
) -> SignedUrlRead:
    url = await service.resume_signed_url(db, current_user.id)
    return SignedUrlRead(url=url, expires_in=settings.scholar_signed_url_expires_seconds)
