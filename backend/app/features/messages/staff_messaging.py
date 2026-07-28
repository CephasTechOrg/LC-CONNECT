"""Staff-to-anyone messaging: start a new conversation without a connection, and search
for who to start it with. Split out from `service.py` (thread listing/paging/sending)
since this is a distinct concern — provisioning, not an existing conversation's traffic.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import MessageThreadRead, RecipientSearchResult
from app.features.messages.service import message_read
from app.models import CampusPosition, Message, Profile, User
from app.shared.policies import can_message_as_staff, users_are_blocked
from app.shared.profiles import profile_load_options
from app.shared.serializers import profile_to_public


async def create_staff_thread(db: AsyncSession, *, actor: User, target_user_id: UUID) -> MessageThreadRead:
    """Get-or-create a `staff_dm` conversation between `actor` and `target_user_id`.

    Bidirectional by design: either side may be the "verified staff" party (a student
    messaging a directory contact, or a staff member messaging a student). Requires at
    least one side to satisfy `can_message_as_staff` — see that policy for the bar staff
    must clear (enabled + verified position).
    """
    from app.shared.conversations import ensure_staff_dm_conversation

    if target_user_id == actor.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='You cannot message yourself')

    target = await db.get(User, target_user_id)
    if (
        target is None
        or not target.is_active
        or target.status != 'active'
        or not target.is_verified
        or target.deleted_at is not None
    ):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found')

    if not await can_message_as_staff(db, actor) and not await can_message_as_staff(db, target):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Staff messaging requires a verified campus position',
        )
    if await users_are_blocked(db, actor.id, target.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Messaging is blocked')

    conversation = await ensure_staff_dm_conversation(db, actor.id, target.id)
    await db.commit()

    profile = (
        await db.execute(
            select(Profile).options(*profile_load_options()).where(Profile.user_id == target.id)
        )
    ).scalar_one()
    position = await _verified_primary_position(db, target.id)
    latest_msg = (
        await db.execute(
            select(Message)
            .where(Message.conversation_id == conversation.id)
            .order_by(Message.created_at.desc(), Message.id.desc())
            .limit(1)
        )
    ).scalar_one_or_none()

    return MessageThreadRead(
        conversation_id=conversation.id,
        kind='staff_dm',
        match_id=None,
        partner=profile_to_public(profile),
        partner_position_title=position.official_title if position else None,
        partner_department=position.department if position else None,
        latest_message=message_read(latest_msg) if latest_msg else None,
    )


async def _verified_primary_position(db: AsyncSession, user_id: UUID) -> CampusPosition | None:
    return (
        await db.execute(
            select(CampusPosition).where(
                CampusPosition.user_id == user_id,
                CampusPosition.is_primary.is_(True),
                CampusPosition.is_active.is_(True),
                CampusPosition.status == 'verified',
            )
        )
    ).scalar_one_or_none()


async def search_recipients(
    db: AsyncSession, *, actor: User, query: str, limit: int = 20
) -> list[RecipientSearchResult]:
    """Users `actor` (a verified staff messenger) may start a new conversation with.

    Matches on display name or official title, active + verified accounts only, excluding
    `actor` and anyone they've blocked (in either direction).
    """
    pattern = f'%{query.strip().lower()}%'
    rows = (
        await db.execute(
            select(User, Profile, CampusPosition)
            .join(Profile, Profile.user_id == User.id)
            .outerjoin(
                CampusPosition,
                (CampusPosition.user_id == User.id)
                & CampusPosition.is_primary.is_(True)
                & CampusPosition.is_active.is_(True)
                & (CampusPosition.status == 'verified'),
            )
            .where(
                User.id != actor.id,
                User.is_active.is_(True),
                User.status == 'active',
                User.is_verified.is_(True),
                User.deleted_at.is_(None),
                or_(
                    func.lower(Profile.display_name).like(pattern),
                    func.lower(CampusPosition.official_title).like(pattern),
                ),
            )
            .order_by(Profile.display_name.asc())
            .limit(limit)
        )
    ).all()

    results: list[RecipientSearchResult] = []
    for user, profile, position in rows:
        if await users_are_blocked(db, actor.id, user.id):
            continue
        results.append(
            RecipientSearchResult(
                user_id=user.id,
                display_name=profile.display_name,
                avatar_url=profile.avatar_url,
                role=user.role,
                position_title=position.official_title if position else None,
                department=position.department if position else None,
            )
        )
    return results
