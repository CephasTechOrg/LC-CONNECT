from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.features.messages.schema import MessageCreate, MessageRead, MessageThreadRead
from app.features.messages.service import get_match_for_user, message_read, partner_id
from app.models import Match, Message, Profile, User
from app.shared.policies import users_are_blocked
from app.shared.profiles import profile_load_options
from app.shared.serializers import profile_to_public

router = APIRouter(prefix='/messages', tags=['messages'])


@router.get('/threads', response_model=list[MessageThreadRead])
async def list_threads(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    matches = (await db.execute(select(Match).where(or_(Match.user_a_id == current_user.id, Match.user_b_id == current_user.id)).order_by(Match.created_at.desc()))).scalars().all()

    if not matches:
        return []

    match_ids = [m.id for m in matches]
    latest_messages = (
        await db.execute(
            select(Message)
            .where(Message.match_id.in_(match_ids))
            .distinct(Message.match_id)
            .order_by(Message.match_id, Message.created_at.desc())
        )
    ).scalars().all()
    message_map = {m.match_id: m for m in latest_messages}

    partner_ids = [partner_id(match, current_user) for match in matches]
    profiles = (await db.execute(select(Profile).options(*profile_load_options()).where(Profile.user_id.in_(partner_ids)))).scalars().all()
    profile_map = {p.user_id: p for p in profiles}

    threads: list[MessageThreadRead] = []
    for match in matches:
        latest = message_map.get(match.id)
        partner_profile = profile_map.get(partner_id(match, current_user))
        if partner_profile:
            threads.append(MessageThreadRead(match_id=match.id, partner=profile_to_public(partner_profile), latest_message=message_read(latest) if latest else None))
    return threads


@router.get('/threads/{match_id}', response_model=list[MessageRead])
async def get_thread(match_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await get_match_for_user(db, match_id, current_user)
    messages = (await db.execute(select(Message).where(Message.match_id == match_id).order_by(Message.created_at.asc()))).scalars().all()
    return [message_read(message) for message in messages]


@router.post('/threads/{match_id}', response_model=MessageRead, status_code=status.HTTP_201_CREATED)
async def send_message(match_id: UUID, payload: MessageCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    match = await get_match_for_user(db, match_id, current_user)
    if await users_are_blocked(db, current_user.id, partner_id(match, current_user)):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Messaging is blocked')
    message = Message(match_id=match.id, sender_id=current_user.id, body=payload.body.strip())
    db.add(message)
    await db.commit()
    await db.refresh(message)
    return message_read(message)
