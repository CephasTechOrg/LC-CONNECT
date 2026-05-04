from fastapi import APIRouter, Depends, Query
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.dependencies import get_current_user
from app.models import Block, ConnectionRequest, Match, Profile, User, UserLanguage
from app.routers.profiles import get_profile_by_user_id
from app.schemas import DiscoveryCard
from app.services import calculate_match, profile_to_public

router = APIRouter(prefix='/discovery', tags=['discovery'])


@router.get('/cards', response_model=list[DiscoveryCard])
async def get_discovery_cards(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db), limit: int = Query(default=20, ge=1, le=50)) -> list[DiscoveryCard]:
    current_profile = await get_profile_by_user_id(db, current_user.id)

    blocks = (await db.execute(select(Block).where(or_(Block.blocker_id == current_user.id, Block.blocked_id == current_user.id)))).scalars().all()
    blocked_ids = {b.blocked_id if b.blocker_id == current_user.id else b.blocker_id for b in blocks}

    matches = (await db.execute(select(Match).where(or_(Match.user_a_id == current_user.id, Match.user_b_id == current_user.id)))).scalars().all()
    matched_ids = {m.user_b_id if m.user_a_id == current_user.id else m.user_a_id for m in matches}

    requests = (await db.execute(select(ConnectionRequest).where(ConnectionRequest.status == 'pending', or_(ConnectionRequest.sender_id == current_user.id, ConnectionRequest.receiver_id == current_user.id)))).scalars().all()
    pending_ids = {r.receiver_id if r.sender_id == current_user.id else r.sender_id for r in requests}

    excluded = {current_user.id} | blocked_ids | matched_ids | pending_ids
    result = await db.execute(
        select(Profile)
        .join(User, User.id == Profile.user_id)
        .options(selectinload(Profile.interests), selectinload(Profile.looking_for_options), selectinload(Profile.languages).selectinload(UserLanguage.language))
        .where(Profile.user_id.not_in(excluded), Profile.is_hidden.is_(False), Profile.profile_completed.is_(True), User.is_active.is_(True), User.status == 'active')
        .limit(150)
    )
    candidates = result.scalars().unique().all()

    scored = []
    for candidate in candidates:
        score, reasons = calculate_match(current_profile, candidate)
        scored.append((score, reasons, candidate))
    scored.sort(key=lambda item: item[0], reverse=True)

    cards: list[DiscoveryCard] = []
    for score, reasons, profile in scored[:limit]:
        public = profile_to_public(profile)
        cards.append(DiscoveryCard(
            profile_id=public.id,
            user_id=public.user_id,
            display_name=public.display_name,
            avatar_url=public.avatar_url,
            major=public.major,
            class_year=public.class_year,
            bio=public.bio,
            interests=public.interests,
            languages_spoken=public.languages_spoken,
            languages_learning=public.languages_learning,
            looking_for=public.looking_for,
            looking_for_codes=public.looking_for_codes,
            match_score=score,
            match_reasons=reasons,
        ))
    return cards
