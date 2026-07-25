from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import require_verified_student
from app.features.connections.schema import (
    ConnectionRequestCreate,
    ConnectionRequestEnriched,
    ConnectionRequestRead,
    MatchRead,
)
from app.features.connections.service import existing_match, ordered_pair
from app.models import ConnectionRequest, Match, Profile, User
from app.shared.conversations import ensure_dm_conversation
from app.shared.policies import users_are_blocked
from app.shared.profiles import get_profile_by_user_id, profile_load_options
from app.shared.rate_limit import connection_request_limit
from app.shared.serializers import profile_to_public

router = APIRouter(prefix='/connections', tags=['connections'])


async def _notify(user_id: UUID, notif_type: str, actor_id: UUID) -> None:
    """Fire an in-app notification for a connection event. Lazy import avoids a module-load
    cycle with the realtime package."""
    from app.features.realtime.runtime import emit_notification

    await emit_notification(user_id=user_id, notif_type=notif_type, actor_id=actor_id)


@router.post(
    '/request',
    response_model=ConnectionRequestRead,
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(connection_request_limit)],
)
async def send_connection_request(payload: ConnectionRequestCreate, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)) -> ConnectionRequestRead:
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
        new_match = Match(user_a_id=left, user_b_id=right)
        db.add(new_match)
        try:
            await db.flush()
        except IntegrityError:
            # Both sides connected back at the same instant — the other transaction created
            # the match. That's success, not an error.
            await db.rollback()
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='You are already matched') from None
        await ensure_dm_conversation(db, new_match)  # every match gets its conversation
        await db.commit()
        await db.refresh(reverse_request)
        # Connecting back accepts their pending request → tell them it's a match.
        await _notify(payload.receiver_id, 'connection_accepted', current_user.id)
        return reverse_request

    existing = (await db.execute(select(ConnectionRequest).where(ConnectionRequest.sender_id == current_user.id, ConnectionRequest.receiver_id == payload.receiver_id))).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Connection request already exists')

    request = ConnectionRequest(sender_id=current_user.id, receiver_id=payload.receiver_id, intent=payload.intent, note=payload.note)
    db.add(request)
    try:
        await db.commit()
    except IntegrityError:
        # Race: a concurrent identical request (e.g. a double-tap) won the unique constraint.
        # Return that one instead of surfacing a 500 — the action is idempotent.
        await db.rollback()
        return (await db.execute(select(ConnectionRequest).where(
            ConnectionRequest.sender_id == current_user.id,
            ConnectionRequest.receiver_id == payload.receiver_id,
        ))).scalar_one()
    await db.refresh(request)
    await _notify(payload.receiver_id, 'connection_request', current_user.id)  # "X sent you a request"
    return request


async def _enrich(db: AsyncSession, requests: list[ConnectionRequest], partner_user_id_fn) -> list[ConnectionRequestEnriched]:
    result: list[ConnectionRequestEnriched] = []
    for req in requests:
        try:
            profile = await get_profile_by_user_id(db, partner_user_id_fn(req))
            partner = profile_to_public(profile)
        except Exception:
            partner = None
        result.append(ConnectionRequestEnriched(
            id=req.id,
            sender_id=req.sender_id,
            receiver_id=req.receiver_id,
            intent=req.intent,
            note=req.note,
            status=req.status,
            created_at=req.created_at,
            partner_profile=partner,
        ))
    return result


@router.get('/incoming', response_model=list[ConnectionRequestEnriched])
async def incoming_requests(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    requests = list((await db.execute(select(ConnectionRequest).where(ConnectionRequest.receiver_id == current_user.id, ConnectionRequest.status == 'pending').order_by(ConnectionRequest.created_at.desc()))).scalars().all())
    return await _enrich(db, requests, lambda r: r.sender_id)


@router.get('/outgoing', response_model=list[ConnectionRequestEnriched])
async def outgoing_requests(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    requests = list((await db.execute(select(ConnectionRequest).where(ConnectionRequest.sender_id == current_user.id, ConnectionRequest.status == 'pending').order_by(ConnectionRequest.created_at.desc()))).scalars().all())
    return await _enrich(db, requests, lambda r: r.receiver_id)


@router.post('/{request_id}/accept', response_model=MatchRead)
async def accept_request(request_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
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
    await ensure_dm_conversation(db, match)  # every match gets its conversation
    await db.commit()
    await db.refresh(match)
    await _notify(request.sender_id, 'connection_accepted', current_user.id)  # tell the sender
    partner_id = match.user_b_id if match.user_a_id == current_user.id else match.user_a_id
    partner_profile = await get_profile_by_user_id(db, partner_id)
    return MatchRead(id=match.id, user_a_id=match.user_a_id, user_b_id=match.user_b_id, created_at=match.created_at, partner=profile_to_public(partner_profile))


@router.post('/{request_id}/decline', response_model=ConnectionRequestRead)
async def decline_request(request_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    request = await db.get(ConnectionRequest, request_id)
    if request is None or request.receiver_id != current_user.id or request.status != 'pending':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Pending request not found')
    request.status = 'declined'
    request.responded_at = datetime.now(UTC)
    await db.commit()
    await db.refresh(request)
    return request


@router.get('/matches', response_model=list[MatchRead])
async def list_matches(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
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
