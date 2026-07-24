"""Group endpoints. Roles/permissions come from `policies.py`; membership + join flows +
transactional capacity come from `service.py`. Routers stay thin."""

from uuid import UUID

from fastapi import APIRouter, Body, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.dependencies import require_verified_student
from app.features.groups import service
from app.features.groups.policies import GroupAction, can
from app.features.groups.schema import (
    GroupCreate,
    GroupMemberRead,
    GroupRead,
    GroupSummary,
    GroupUpdate,
    JoinResult,
)
from app.models import Conversation, Group, User
from app.shared.image_processing import sanitize_avatar
from app.shared.storage import storage_service

router = APIRouter(prefix='/groups', tags=['groups'])


async def _load_group(db: AsyncSession, group_id: UUID) -> Group:
    group = await db.get(Group, group_id)
    if group is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Group not found')
    return group


async def _visible_group(group_id: UUID, current_user: User, db: AsyncSession) -> tuple[Group, object]:
    """The group + the caller's membership, 404 if the group isn't visible to them."""
    group = await _load_group(db, group_id)
    member = await service.membership(db, group.conversation_id, current_user.id)
    service.assert_group_visible(group, member)
    return group, member


def _active_role(member) -> str | None:
    return member.role if (member is not None and member.status == 'active') else None


def _require(member, action: GroupAction) -> None:
    if not can(_active_role(member), action):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Not allowed')


# ── lifecycle ─────────────────────────────────────────────────────────────────────

@router.post('', response_model=GroupRead, status_code=status.HTTP_201_CREATED)
async def create_group(payload: GroupCreate, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group = await service.create_group(db, current_user, payload)
    await db.commit()
    member = await service.membership(db, group.conversation_id, current_user.id)
    return await service.to_read(db, group, member)


@router.get('/me', response_model=list[GroupSummary])
async def list_my_groups(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    return [await service.to_summary(db, group, member) for group, member in await service.my_groups(db, current_user.id)]


@router.get('/invites', response_model=list[GroupSummary])
async def list_my_invites(current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    """Groups the user has been invited to (including private/unlisted ones not in discovery)."""
    return [await service.to_summary(db, group, member) for group, member in await service.my_invites(db, current_user.id)]


@router.get('/discover', response_model=list[GroupSummary])
async def discover(
    q: str | None = Query(default=None),
    category: str | None = Query(default=None),
    limit: int = Query(default=30, ge=1, le=100),
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
):
    groups = await service.discover_groups(db, query=q, category=category, limit=limit)
    result: list[GroupSummary] = []
    for group in groups:
        member = await service.membership(db, group.conversation_id, current_user.id)
        result.append(await service.to_summary(db, group, member))
    return result


@router.get('/{group_id}', response_model=GroupRead)
async def get_group(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    return await service.to_read(db, group, member)


@router.patch('/{group_id}', response_model=GroupRead)
async def edit_group(group_id: UUID, payload: GroupUpdate, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.EDIT_GROUP)
    await service.update_group(db, group, payload.model_dump(exclude_unset=True))
    await db.commit()
    return await service.to_read(db, group, member)


@router.post('/{group_id}/avatar', response_model=GroupRead)
async def upload_group_avatar(
    group_id: UUID,
    file: UploadFile = File(...),
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.EDIT_GROUP)
    data = await file.read()
    if len(data) > settings.max_profile_image_mb * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail='Image is too large')
    clean, content_type = sanitize_avatar(data)  # validates bytes + strips EXIF/GPS (same as profiles)
    await service.set_avatar(db, group, storage_service.upload_group_image(group.id, content_type, clean))
    await db.commit()
    return await service.to_read(db, group, member)


@router.delete('/{group_id}', status_code=status.HTTP_204_NO_CONTENT)
async def delete_group(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.DELETE_GROUP)  # owner only
    # Delete the conversation: the group (via its ON DELETE CASCADE FK), members, and messages
    # all cascade from it.
    conversation = await db.get(Conversation, group.conversation_id)
    await db.delete(conversation)
    await db.commit()


# ── join / invite / leave ─────────────────────────────────────────────────────────

@router.post('/{group_id}/join', response_model=JoinResult)
async def join(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, _ = await _visible_group(group_id, current_user, db)
    result = await service.join_group(db, group, current_user)
    await db.commit()
    return result


@router.get('/{group_id}/members', response_model=list[GroupMemberRead])
async def list_members(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    if _active_role(member) is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Members only')
    return await service.members_read(db, group.conversation_id)


@router.get('/{group_id}/requests', response_model=list[GroupMemberRead])
async def list_requests(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.APPROVE_REQUEST)
    return await service.members_read(db, group.conversation_id, member_status='requested')


@router.post('/{group_id}/requests/{user_id}/approve', status_code=status.HTTP_204_NO_CONTENT)
async def approve(group_id: UUID, user_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.APPROVE_REQUEST)
    await service.approve_request(db, group, user_id)
    await db.commit()


@router.post('/{group_id}/requests/{user_id}/reject', status_code=status.HTTP_204_NO_CONTENT)
async def reject(group_id: UUID, user_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.APPROVE_REQUEST)
    await service.reject_request(db, group, user_id)
    await db.commit()


@router.post('/{group_id}/invites', status_code=status.HTTP_204_NO_CONTENT)
async def invite(group_id: UUID, user_id: UUID = Body(..., embed=True), current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.INVITE)
    await service.invite_user(db, group, user_id, invited_by=current_user.id)
    await db.commit()


@router.post('/{group_id}/invites/accept', response_model=JoinResult)
async def accept_invite(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group = await _load_group(db, group_id)  # invited users may not "see" a private group yet
    result = await service.accept_invite(db, group, current_user)
    await db.commit()
    return result


@router.post('/{group_id}/invites/decline', status_code=status.HTTP_204_NO_CONTENT)
async def decline_invite(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group = await _load_group(db, group_id)  # invited users may not "see" a private group yet
    await service.decline_invite(db, group, current_user)
    await db.commit()


@router.delete('/{group_id}/members/me', status_code=status.HTTP_204_NO_CONTENT)
async def leave(group_id: UUID, current_user: User = Depends(require_verified_student), db: AsyncSession = Depends(get_db)):
    group, member = await _visible_group(group_id, current_user, db)
    if _active_role(member) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Not a member')
    await service.leave_group(db, group, member)
    await db.commit()


# Declared before `/members/{user_id}` so the literal `me` wins over the UUID path param.
@router.patch('/{group_id}/members/me', status_code=status.HTTP_204_NO_CONTENT)
async def set_my_mute(
    group_id: UUID,
    muted: bool = Body(..., embed=True),
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
):
    group, member = await _visible_group(group_id, current_user, db)
    if _active_role(member) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Not a member')
    await service.set_mute(db, member, muted)
    await db.commit()


@router.patch('/{group_id}/members/{user_id}', status_code=status.HTTP_204_NO_CONTENT)
async def change_member_role(
    group_id: UUID,
    user_id: UUID,
    role: str = Body(..., embed=True),
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.EDIT_GROUP)
    await service.change_role(db, group, member, user_id, role)
    await db.commit()


@router.post('/{group_id}/transfer', status_code=status.HTTP_204_NO_CONTENT)
async def transfer_ownership(
    group_id: UUID,
    user_id: UUID = Body(..., embed=True),
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.TRANSFER_OWNERSHIP)  # owner only
    await service.transfer_ownership(db, group, member, user_id)
    await db.commit()


@router.delete('/{group_id}/members/{user_id}', status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(
    group_id: UUID,
    user_id: UUID,
    ban: bool = Query(default=False),
    current_user: User = Depends(require_verified_student),
    db: AsyncSession = Depends(get_db),
):
    group, member = await _visible_group(group_id, current_user, db)
    _require(member, GroupAction.BAN_MEMBER if ban else GroupAction.REMOVE_MEMBER)
    await service.remove_member(db, group, member, user_id, ban=ban)
    await db.commit()
    # Close the removed member's live subscription so they stop receiving the group's messages.
    # Lazy import avoids a module-load cycle with the realtime package.
    from app.features.realtime.protocol import ErrorCode, error
    from app.features.realtime.runtime import manager as ws_manager

    await ws_manager.revoke_member(
        group.conversation_id, user_id, error(ErrorCode.FORBIDDEN, 'Removed from group')
    )
