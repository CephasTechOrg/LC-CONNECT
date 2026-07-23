from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_verified_student
from app.features.profiles.schema import MyProfileRead, ProfileUpdate
from app.features.profiles.service import (
    compute_profile_completed,
    get_looking_for_options,
    get_or_create_interests,
    get_or_create_languages,
)
from app.models import ActivityParticipant, Match, Message, Profile, User, UserLanguage
from app.shared.image_processing import sanitize_avatar
from app.shared.policies import assert_profile_visible
from app.shared.profiles import get_profile_by_user_id, profile_load_options
from app.shared.schemas import ProfilePublic
from app.shared.serializers import profile_to_public
from app.shared.storage import storage_service

router = APIRouter(prefix='/profiles', tags=['profiles'])


@router.get('/me', response_model=MyProfileRead)
async def get_my_profile(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)) -> MyProfileRead:
    profile = await get_profile_by_user_id(db, current_user.id)

    connection_count = int((await db.execute(
        select(func.count(Match.id)).where(
            or_(Match.user_a_id == current_user.id, Match.user_b_id == current_user.id)
        )
    )).scalar_one())

    activity_count = int((await db.execute(
        select(func.count(ActivityParticipant.id)).where(
            ActivityParticipant.user_id == current_user.id
        )
    )).scalar_one())

    message_count = int((await db.execute(
        select(func.count(Message.id)).where(
            Message.sender_id == current_user.id
        )
    )).scalar_one())

    return MyProfileRead(
        **profile_to_public(profile).model_dump(),
        allow_messages_from_matches_only=profile.allow_messages_from_matches_only,
        show_profile_to_verified_only=profile.show_profile_to_verified_only,
        connection_count=connection_count,
        activity_count=activity_count,
        message_count=message_count,
    )


@router.patch('/me', response_model=ProfilePublic)
async def update_my_profile(payload: ProfileUpdate, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)) -> ProfilePublic:
    profile = await get_profile_by_user_id(db, current_user.id)
    data = payload.model_dump(exclude_unset=True)

    scalar_fields = {
        'display_name', 'pronouns', 'major', 'class_year', 'country_state', 'campus', 'bio',
        'is_hidden', 'allow_messages_from_matches_only', 'show_profile_to_verified_only',
    }
    for field in scalar_fields:
        if field in data:
            setattr(profile, field, data[field])

    if payload.interests is not None:
        profile.interests = await get_or_create_interests(db, payload.interests)
    if payload.looking_for_codes is not None:
        profile.looking_for_options = await get_looking_for_options(db, payload.looking_for_codes)
    if payload.languages_spoken is not None or payload.languages_learning is not None:
        # clear() alone is not enough: SQLAlchemy may INSERT the replacements
        # before DELETEing the old rows in the same flush, which trips
        # uq_user_language_kind. Flush the orphan deletes first.
        profile.languages.clear()
        await db.flush()
        spoken = await get_or_create_languages(db, payload.languages_spoken or [])
        learning = await get_or_create_languages(db, payload.languages_learning or [])
        for language in spoken:
            profile.languages.append(UserLanguage(profile_id=profile.id, language_id=language.id, kind='speaks'))
        for language in learning:
            profile.languages.append(UserLanguage(profile_id=profile.id, language_id=language.id, kind='learning'))

    profile.profile_completed = compute_profile_completed(profile)
    await db.commit()
    return profile_to_public(await get_profile_by_user_id(db, current_user.id))


@router.post('/me/avatar', response_model=ProfilePublic)
async def upload_my_avatar(file: UploadFile = File(...), current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)) -> ProfilePublic:
    # Byte cap first (cheap, before we decode), then sanitize: sanitize_avatar validates
    # the real image bytes (not the spoofable content-type header), strips EXIF/GPS, and
    # re-encodes to a clean JPEG. We store only that sanitized output.
    data = await file.read()
    if len(data) > settings.max_profile_image_mb * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail='Profile image is too large')
    clean_data, content_type = sanitize_avatar(data)
    profile = await get_profile_by_user_id(db, current_user.id)
    profile.avatar_url = storage_service.upload_profile_image(current_user.id, content_type, clean_data)
    await db.commit()
    return profile_to_public(await get_profile_by_user_id(db, current_user.id))


@router.get('/{profile_id}', response_model=ProfilePublic)
async def get_profile(profile_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)) -> ProfilePublic:
    profile = (await db.execute(select(Profile).options(*profile_load_options()).where(Profile.id == profile_id))).scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Profile not found')
    # Enforce hidden / verified-only / block visibility (was only checking is_hidden).
    await assert_profile_visible(db, viewer=current_user, profile=profile)
    return profile_to_public(profile)
