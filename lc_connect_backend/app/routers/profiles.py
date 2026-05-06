from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user
from app.models import ActivityParticipant, Interest, Language, LookingForOption, Match, Message, Profile, User, UserLanguage
from app.schemas import MyProfileRead, ProfilePublic, ProfileUpdate
from app.services import profile_to_public, storage_service

router = APIRouter(prefix='/profiles', tags=['profiles'])


def profile_load_options():
    return [
        selectinload(Profile.interests),
        selectinload(Profile.looking_for_options),
        selectinload(Profile.languages).selectinload(UserLanguage.language),
    ]


async def get_profile_by_user_id(db: AsyncSession, user_id: UUID) -> Profile:
    profile = (await db.execute(select(Profile).options(*profile_load_options()).where(Profile.user_id == user_id))).scalar_one_or_none()
    if profile is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Profile not found')
    return profile


async def get_or_create_interests(db: AsyncSession, names: list[str]) -> list[Interest]:
    items: list[Interest] = []
    for name in sorted({name.strip().title() for name in names if name.strip()}):
        item = (await db.execute(select(Interest).where(Interest.name == name))).scalar_one_or_none()
        if item is None:
            item = Interest(name=name, category='custom')
            db.add(item)
            await db.flush()
        items.append(item)
    return items


async def get_or_create_languages(db: AsyncSession, names: list[str]) -> list[Language]:
    items: list[Language] = []
    for name in sorted({name.strip().title() for name in names if name.strip()}):
        item = (await db.execute(select(Language).where(Language.name == name))).scalar_one_or_none()
        if item is None:
            item = Language(name=name)
            db.add(item)
            await db.flush()
        items.append(item)
    return items


async def get_looking_for_options(db: AsyncSession, codes: list[str]) -> list[LookingForOption]:
    clean_codes = sorted({code.strip().lower() for code in codes if code.strip()})
    return list((await db.execute(select(LookingForOption).where(LookingForOption.code.in_(clean_codes)))).scalars().all())


def compute_profile_completed(profile: Profile) -> bool:
    return bool(profile.display_name and profile.major and profile.class_year and profile.looking_for_options)


@router.get('/me', response_model=MyProfileRead)
async def get_my_profile(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> MyProfileRead:
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
async def update_my_profile(payload: ProfileUpdate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> ProfilePublic:
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
        profile.languages.clear()
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
async def upload_my_avatar(file: UploadFile = File(...), current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> ProfilePublic:
    if file.content_type not in {'image/jpeg', 'image/png', 'image/webp'}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Only JPEG, PNG, and WebP images are allowed')
    data = await file.read()
    if len(data) > settings.max_profile_image_mb * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail='Profile image is too large')
    profile = await get_profile_by_user_id(db, current_user.id)
    profile.avatar_url = storage_service.upload_profile_image(current_user.id, file.filename or 'avatar.jpg', file.content_type or 'image/jpeg', data)
    await db.commit()
    return profile_to_public(await get_profile_by_user_id(db, current_user.id))


@router.get('/{profile_id}', response_model=ProfilePublic)
async def get_profile(profile_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> ProfilePublic:
    profile = (await db.execute(select(Profile).options(*profile_load_options()).where(Profile.id == profile_id))).scalar_one_or_none()
    if profile is None or profile.is_hidden:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Profile not found')
    return profile_to_public(profile)
