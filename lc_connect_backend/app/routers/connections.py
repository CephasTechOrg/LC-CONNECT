from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user
from app.models import ConnectionRequest, Match, Profile, User
from app.routers.profiles import get_profile_by_user_id, profile_load_options
from app.schemas import ConnectionRequestCreate, ConnectionRequestRead, MatchRead
from app.services import profile_to_public, users_are_blocked

router = APIRouter(prefix='/connections', tags=['connections'])


def ordered_pair(user_a: UUID, user_b: UUID) -> tuple[UUID, UUID]:
    ordered = sorted([user_a, user_b], key=lambda value: str(value))
    return ordered[0], ordered[1]


async def existing_match(db: AsyncSession, user_a: UUID, user_b: UUID) -> Match | None:
    left, right = ordered_pair(user_a, user_b)
    return (await db.execute(select(Match).where(Match.user_a_id == left, Match.user_b_id == right))).scalar_one_or_none()


@router.post('/request', response_model=ConnectionRequestRead, status_code=status.HTTP_201_CREATED)
async def send_connection_request(payload: ConnectionRequestCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)) -> ConnectionRequestRead:
    if payload.receiver_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='You cannot connect with yourself')
    receiver = await db.get(User, payload.receiver_id)
    if receiver is None or not receiver.is_active or receiver.status != 'active':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')
    if await users_are_blocked(db, current_user.id, payload.receiver_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Connection is not allowed')
    if await existing_match(db, current_user.id, payload.receiver_id):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='You are already matched')

    reverse_request = (await db.execute(select(ConnectionRequest).where(ConnectionRequest.sender_id == payload.receiver_id, ConnectionRequest.receiver_id == current_user.id, ConnectionRequest.status == 'pending'))).scalar_one_or_none()
    if reverse_request:
        reverse_request.status = 'accepted'
        reverse_request.responded_at = datetime.now(UTC)
        left, right = ordered_pair(current_user.id, payload.receiver_id)
        db.add(Match(user_a_id=left, user_b_id=right))
        await db.commit()
        await db.refresh(reverse_request)
        return reverse_request

    existing = (await db.execute(select(ConnectionRequest).where(ConnectionRequest.sender_id == current_user.id, ConnectionRequest.receiver_id == payload.receiver_id))).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Connection request already exists')

    request = ConnectionRequest(sender_id=current_user.id, receiver_id=payload.receiver_id, intent=payload.intent, note=payload.note)
    db.add(request)
    await db.commit()
    await db.refresh(request)
    return request


@router.get('/incoming', response_model=list[ConnectionRequestRead])
async def incoming_requests(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return list((await db.execute(select(ConnectionRequest).where(ConnectionRequest.receiver_id == current_user.id, ConnectionRequest.status == 'pending').order_by(ConnectionRequest.created_at.desc()))).scalars().all())


@router.get('/outgoing', response_model=list[ConnectionRequestRead])
async def outgoing_requests(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return list((await db.execute(select(ConnectionRequest).where(ConnectionRequest.sender_id == current_user.id, ConnectionRequest.status == 'pending').order_by(ConnectionRequest.created_at.desc()))).scalars().all())


@router.post('/{request_id}/accept', response_model=MatchRead)
async def accept_request(request_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    request = await db.get(ConnectionRequest, request_id)
    if request is None or request.receiver_id != current_user.id or request.status != 'pending':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Pending request not found')
    if await users_are_blocked(db, request.sender_id, request.receiver_id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Connection is not allowed')

    request.status = 'accepted'
    request.responded_at = datetime.now(UTC)
    left, right = ordered_pair(request.sender_id, request.receiver_id)
    match = await existing_match(db, request.sender_id, request.receiver_id)
    if match is None:
        match = Match(user_a_id=left, user_b_id=right)
        db.add(match)
        await db.flush()
    await db.commit()
    await db.refresh(match)
    partner_id = match.user_b_id if match.user_a_id == current_user.id else match.user_a_id
    partner_profile = await get_profile_by_user_id(db, partner_id)
    return MatchRead(id=match.id, user_a_id=match.user_a_id, user_b_id=match.user_b_id, created_at=match.created_at, partner=profile_to_public(partner_profile))


@router.post('/{request_id}/decline', response_model=ConnectionRequestRead)
async def decline_request(request_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    request = await db.get(ConnectionRequest, request_id)
    if request is None or request.receiver_id != current_user.id or request.status != 'pending':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Pending request not found')
    request.status = 'declined'
    request.responded_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(request)
    return request


@router.get('/matches', response_model=list[MatchRead])
async def list_matches(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    matches = list((await db.execute(select(Match).where(or_(Match.user_a_id == current_user.id, Match.user_b_id == current_user.id)).order_by(Match.created_at.desc()))).scalars().all())
    
    if not matches:
        return []

    partner_ids = [match.user_b_id if match.user_a_id == current_user.id else match.user_a_id for match in matches]
    profiles = (await db.execute(select(Profile).options(*profile_load_options()).where(Profile.user_id.in_(partner_ids)))).scalars().all()
    profile_map = {p.user_id: p for p in profiles}

    output: list[MatchRead] = []
    for match in matches:
        partner_id = match.user_b_id if match.user_a_id == current_user.id else match.user_a_id
        partner_profile = profile_map.get(partner_id)
        if partner_profile:
            output.append(MatchRead(id=match.id, user_a_id=match.user_a_id, user_b_id=match.user_b_id, created_at=match.created_at, partner=profile_to_public(partner_profile)))
    return output
