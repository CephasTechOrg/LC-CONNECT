"""Groups domain logic: create, membership, join flows, capacity, visibility.

Membership reuses `ConversationMember` (the same table DMs use). Capacity is enforced
**transactionally** — a `SELECT ... FOR UPDATE` on the group row serializes concurrent joins,
so `max_members` can never be exceeded (unlike the Activities count-then-insert pattern).
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.groups.policies import can_moderate
from app.features.groups.schema import GroupCreate, GroupMemberRead, GroupRead, GroupSummary, JoinResult
from app.models import Conversation, ConversationMember, Group, Profile, User
from app.shared.profiles import profile_load_options
from app.shared.serializers import profile_to_public

ACTIVE = 'active'


# ── membership lookups ───────────────────────────────────────────────────────────

async def membership(db: AsyncSession, conversation_id: UUID, user_id: UUID) -> ConversationMember | None:
    return (
        await db.execute(
            select(ConversationMember).where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.user_id == user_id,
            )
        )
    ).scalar_one_or_none()


async def active_member_count(db: AsyncSession, conversation_id: UUID) -> int:
    return int(
        (
            await db.execute(
                select(func.count()).select_from(ConversationMember).where(
                    ConversationMember.conversation_id == conversation_id,
                    ConversationMember.status == ACTIVE,
                )
            )
        ).scalar()
    )


# ── visibility ───────────────────────────────────────────────────────────────────

def assert_group_visible(group: Group, member: ConversationMember | None) -> None:
    """404 (never reveal existence) if a private group is viewed by a non-member. `public` and
    `unlisted` are viewable by anyone with the id; only *discovery* differs for `unlisted`."""
    is_member = member is not None and member.status == ACTIVE
    if group.visibility == 'private' and not is_member:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Group not found')


# ── serialization ────────────────────────────────────────────────────────────────

async def to_summary(db: AsyncSession, group: Group, viewer_member: ConversationMember | None) -> GroupSummary:
    return GroupSummary(
        id=group.id,
        name=group.name,
        avatar_url=group.avatar_url,
        category=group.category,
        visibility=group.visibility,
        join_policy=group.join_policy,
        member_count=await active_member_count(db, group.conversation_id),
        max_members=group.max_members,
        my_status=viewer_member.status if viewer_member else None,
    )


async def to_read(db: AsyncSession, group: Group, viewer_member: ConversationMember | None) -> GroupRead:
    summary = await to_summary(db, group, viewer_member)
    return GroupRead(
        **summary.model_dump(),
        description=group.description,
        owner_id=group.owner_id,
        conversation_id=group.conversation_id,
        my_role=viewer_member.role if (viewer_member and viewer_member.status == ACTIVE) else None,
        created_at=group.created_at,
    )


# ── create ───────────────────────────────────────────────────────────────────────

async def create_group(db: AsyncSession, owner: User, payload: GroupCreate) -> Group:
    conversation = Conversation(kind='group')
    db.add(conversation)
    await db.flush()

    group = Group(
        name=payload.name.strip(),
        description=payload.description,
        category=payload.category,
        visibility=payload.visibility,
        join_policy=payload.join_policy,
        owner_id=owner.id,
        conversation_id=conversation.id,
        max_members=payload.max_members,
    )
    db.add(group)
    db.add(
        ConversationMember(
            conversation_id=conversation.id, user_id=owner.id, role='owner', status=ACTIVE
        )
    )
    await db.flush()
    return group


# ── join ─────────────────────────────────────────────────────────────────────────

async def _reserve_capacity(db: AsyncSession, group: Group) -> None:
    """Lock the group row and reject if full. Serializes concurrent joins for this group."""
    locked = (
        await db.execute(select(Group).where(Group.id == group.id).with_for_update())
    ).scalar_one()
    if locked.max_members is not None:
        if await active_member_count(db, locked.conversation_id) >= locked.max_members:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Group is full')


async def join_group(db: AsyncSession, group: Group, user: User) -> JoinResult:
    existing = await membership(db, group.conversation_id, user.id)
    if existing and existing.status == 'banned':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='You cannot join this group')
    if existing and existing.status == ACTIVE:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Already a member')
    if group.join_policy == 'invite':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='This group is invite-only')

    if group.join_policy == 'open':
        await _reserve_capacity(db, group)  # capacity checked under the row lock
        _set_member(existing, db, group, user, status=ACTIVE)
        return JoinResult(status='active', group_id=group.id)

    # approval: capacity is (re)checked at approval time, not here.
    _set_member(existing, db, group, user, status='requested')
    return JoinResult(status='requested', group_id=group.id)


def _set_member(existing, db, group, user, *, status) -> None:
    if existing is None:
        db.add(
            ConversationMember(
                conversation_id=group.conversation_id, user_id=user.id, role='member', status=status
            )
        )
    else:
        existing.status = status


async def approve_request(db: AsyncSession, group: Group, target_user_id: UUID) -> None:
    member = await membership(db, group.conversation_id, target_user_id)
    if member is None or member.status != 'requested':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No pending request')
    await _reserve_capacity(db, group)  # capacity enforced at approval too
    member.status = ACTIVE


async def reject_request(db: AsyncSession, group: Group, target_user_id: UUID) -> None:
    member = await membership(db, group.conversation_id, target_user_id)
    if member is None or member.status != 'requested':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No pending request')
    member.status = 'removed'


async def invite_user(db: AsyncSession, group: Group, target_user_id: UUID, invited_by: UUID) -> None:
    existing = await membership(db, group.conversation_id, target_user_id)
    if existing and existing.status == ACTIVE:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='Already a member')
    if existing and existing.status == 'banned':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='User is banned from this group')
    if existing is None:
        db.add(
            ConversationMember(
                conversation_id=group.conversation_id, user_id=target_user_id,
                role='member', status='invited', invited_by=invited_by,
            )
        )
    else:
        existing.status = 'invited'
        existing.invited_by = invited_by


async def accept_invite(db: AsyncSession, group: Group, user: User) -> JoinResult:
    member = await membership(db, group.conversation_id, user.id)
    if member is None or member.status != 'invited':
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='No pending invite')
    await _reserve_capacity(db, group)
    member.status = ACTIVE
    return JoinResult(status='active', group_id=group.id)


async def leave_group(db: AsyncSession, group: Group, member: ConversationMember) -> None:
    if member.role == 'owner':
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Transfer ownership before leaving the group',
        )
    member.status = 'removed'


async def update_group(db: AsyncSession, group: Group, changes: dict) -> None:
    for field in ('name', 'description', 'category', 'visibility', 'join_policy', 'max_members'):
        if field in changes:
            setattr(group, field, changes[field].strip() if field == 'name' else changes[field])


async def set_avatar(db: AsyncSession, group: Group, url: str) -> None:
    group.avatar_url = url


async def change_role(
    db: AsyncSession, group: Group, actor: ConversationMember, target_user_id: UUID, new_role: str
) -> None:
    """Promote/demote a member (admin↔member). Owner rank is only granted via transfer."""
    if new_role not in {'admin', 'member'}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Role must be admin or member')
    target = await membership(db, group.conversation_id, target_user_id)
    if target is None or target.status != ACTIVE:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Member not found')
    if not can_moderate(actor.role, target.role):  # can't act on equal/higher rank (or the owner)
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Cannot change this member')
    target.role = new_role


async def transfer_ownership(db: AsyncSession, group: Group, owner: ConversationMember, new_owner_id: UUID) -> None:
    """Owner-only. Preserves the "always exactly one owner" invariant: the new owner becomes
    owner and the old owner steps down to admin."""
    target = await membership(db, group.conversation_id, new_owner_id)
    if target is None or target.status != ACTIVE:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Member not found')
    if target.user_id == owner.user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Already the owner')
    owner.role = 'admin'
    target.role = 'owner'
    group.owner_id = new_owner_id


async def remove_member(
    db: AsyncSession, group: Group, actor: ConversationMember, target_user_id: UUID, *, ban: bool
) -> None:
    """Admin/owner removes (or bans) a member. Enforces the moderation rank rule and returns
    the target's user id so the caller can close their live socket."""
    target = await membership(db, group.conversation_id, target_user_id)
    if target is None or target.status not in {ACTIVE, 'requested', 'invited'}:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Member not found')
    if not can_moderate(actor.role, target.role):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Cannot moderate this member')
    target.status = 'banned' if ban else 'removed'


# ── listings ─────────────────────────────────────────────────────────────────────

async def my_groups(db: AsyncSession, user_id: UUID) -> list[tuple[Group, ConversationMember]]:
    rows = (
        await db.execute(
            select(Group, ConversationMember)
            .join(ConversationMember, ConversationMember.conversation_id == Group.conversation_id)
            .where(ConversationMember.user_id == user_id, ConversationMember.status == ACTIVE)
            .order_by(Group.created_at.desc())
        )
    ).all()
    return [(group, member) for group, member in rows]


async def discover_groups(
    db: AsyncSession, *, query: str | None, category: str | None, limit: int
) -> list[Group]:
    stmt = select(Group).where(Group.visibility == 'public')  # unlisted/private are not listed
    if category:
        stmt = stmt.where(Group.category == category)
    if query:
        stmt = stmt.where(Group.name.ilike(f'%{query.strip()}%'))
    stmt = stmt.order_by(Group.created_at.desc()).limit(limit)
    return list((await db.execute(stmt)).scalars().all())


async def members_read(
    db: AsyncSession, conversation_id: UUID, *, member_status: str = ACTIVE
) -> list[GroupMemberRead]:
    members = (
        await db.execute(
            select(ConversationMember)
            .where(
                ConversationMember.conversation_id == conversation_id,
                ConversationMember.status == member_status,
            )
            .order_by(ConversationMember.joined_at.asc())
        )
    ).scalars().all()
    user_ids = [m.user_id for m in members]
    profiles = {
        p.user_id: p
        for p in (
            await db.execute(select(Profile).options(*profile_load_options()).where(Profile.user_id.in_(user_ids)))
        ).scalars().all()
    }
    return [
        GroupMemberRead(
            user_id=m.user_id,
            profile=profile_to_public(profiles[m.user_id]) if m.user_id in profiles else None,
            role=m.role,
            status=m.status,
            joined_at=m.joined_at,
        )
        for m in members
    ]
