from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from supabase import create_client

from app.config import settings
from app.models import Block, Profile
from app.schemas import ProfilePublic


def profile_to_public(profile: Profile) -> ProfilePublic:
    spoken = sorted([row.language.name for row in profile.languages if row.kind == 'speaks'])
    learning = sorted([row.language.name for row in profile.languages if row.kind == 'learning'])
    looking_options = sorted(profile.looking_for_options, key=lambda item: item.name)
    return ProfilePublic(
        id=profile.id,
        user_id=profile.user_id,
        display_name=profile.display_name,
        pronouns=profile.pronouns,
        major=profile.major,
        class_year=profile.class_year,
        country_state=profile.country_state,
        campus=profile.campus,
        bio=profile.bio,
        avatar_url=profile.avatar_url,
        is_hidden=profile.is_hidden,
        profile_completed=profile.profile_completed,
        interests=sorted([interest.name for interest in profile.interests]),
        languages_spoken=spoken,
        languages_learning=learning,
        looking_for=[item.name for item in looking_options],
        looking_for_codes=[item.code for item in looking_options],
    )


def calculate_match(current: Profile, candidate: Profile) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []

    current_interests = {i.name.lower() for i in current.interests}
    candidate_interests = {i.name.lower() for i in candidate.interests}
    common_interests = sorted(current_interests & candidate_interests)
    if common_interests:
        score += min(len(common_interests) * 25, 75)
        reasons.append(f'You both like {common_interests[0].title()}')

    if current.major and candidate.major and current.major.strip().lower() == candidate.major.strip().lower():
        score += 35
        reasons.append(f'Both in {candidate.major}')

    current_looking = {item.code for item in current.looking_for_options}
    candidate_looking = {item.code for item in candidate.looking_for_options}
    common_goals = current_looking & candidate_looking
    if common_goals:
        score += min(len(common_goals) * 20, 60)
        if 'study_partner' in common_goals:
            reasons.append('Both looking for study partners')
        elif 'language_exchange' in common_goals:
            reasons.append('Both open to language exchange')
        elif 'friendship' in common_goals:
            reasons.append('Both looking for friendship')

    current_spoken = {row.language.name.lower() for row in current.languages if row.kind == 'speaks'}
    current_learning = {row.language.name.lower() for row in current.languages if row.kind == 'learning'}
    candidate_spoken = {row.language.name.lower() for row in candidate.languages if row.kind == 'speaks'}
    candidate_learning = {row.language.name.lower() for row in candidate.languages if row.kind == 'learning'}
    if (current_spoken & candidate_learning) or (candidate_spoken & current_learning):
        score += 30
        reasons.append('Good language exchange match')

    if current.class_year and candidate.class_year and current.class_year == candidate.class_year:
        score += 10
        reasons.append(f'Both class of {current.class_year}')

    if not reasons:
        reasons.append('New student to discover')
    return score, reasons[:3]


async def users_are_blocked(db: AsyncSession, user_a: UUID, user_b: UUID) -> bool:
    result = await db.execute(
        select(Block).where(
            or_(
                (Block.blocker_id == user_a) & (Block.blocked_id == user_b),
                (Block.blocker_id == user_b) & (Block.blocked_id == user_a),
            )
        )
    )
    return result.scalar_one_or_none() is not None


class SupabaseStorageService:
    def __init__(self) -> None:
        self.client = None
        if settings.supabase_url and settings.supabase_service_role_key:
            self.client = create_client(settings.supabase_url, settings.supabase_service_role_key)

    def upload_profile_image(self, user_id: UUID, filename: str, content_type: str, data: bytes) -> str:
        if self.client is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Supabase Storage is not configured')

        extension = filename.rsplit('.', 1)[-1].lower() if '.' in filename else 'jpg'
        safe_extension = extension if extension in {'jpg', 'jpeg', 'png', 'webp'} else 'jpg'
        path = f'profiles/{user_id}/avatar.{safe_extension}'
        self.client.storage.from_(settings.supabase_profile_bucket).upload(
            path=path,
            file=data,
            file_options={'content-type': content_type, 'cache-control': '3600', 'upsert': 'true'},
        )
        return str(self.client.storage.from_(settings.supabase_profile_bucket).get_public_url(path))


storage_service = SupabaseStorageService()
