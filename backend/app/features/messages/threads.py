"""The unified inbox: one row per conversation the user is in, DMs and groups alike.

Split out of `service.py` when that file passed 440 lines. The seam is the read model: this
builds the thread list (latest message, partner or group, reaction preview, mute) and nothing
on the send, page or delete paths depends on it.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import GroupThreadInfo, MessageThreadRead
from app.features.messages.service import message_read
from app.models import CampusPosition, Conversation, ConversationMember, Group, Message, Profile
from app.shared.policies import open_staff_thread_ids
from app.shared.profiles import profile_load_options
from app.shared.serializers import profile_to_public

_EPOCH = datetime(1970, 1, 1, tzinfo=UTC)

# Conversation kinds that carry a single "partner" (as opposed to a group).
_PARTNER_KINDS = ('dm', 'staff_dm')


async def list_threads_for_user(db: AsyncSession, user_id: UUID) -> list[MessageThreadRead]:
    """Unified inbox: every conversation the user is an active member of — DMs *and* groups —
    newest activity first. DM rows carry the partner; group rows carry the group."""
    member_rows = (
        await db.execute(
            select(Conversation, ConversationMember.muted)
            .join(ConversationMember, ConversationMember.conversation_id == Conversation.id)
            .where(ConversationMember.user_id == user_id, ConversationMember.status == 'active')
        )
    ).all()
    if not member_rows:
        return []
    conversations = [conv for conv, _ in member_rows]
    muted_ids = {conv.id for conv, muted in member_rows if muted}

    # A staff thread whose staff side lost their position is no longer accessible — drop it
    # here too, so the inbox never lists a thread that would 403 on open.
    open_staff_ids = await open_staff_thread_ids(db, [c.id for c in conversations if c.kind == 'staff_dm'])
    conversations = [c for c in conversations if c.kind != 'staff_dm' or c.id in open_staff_ids]
    if not conversations:
        return []

    conv_ids = [c.id for c in conversations]
    # The newest reaction worth showing per thread (see `latest_reactions_for_threads`). Additive —
    # it decorates the row the loop builds below and never changes the sort or the unread count.
    from app.features.messages.reactions import latest_reactions_for_threads

    reaction_previews = await latest_reactions_for_threads(db, conv_ids, owner_id=user_id)
    latest = (
        await db.execute(
            select(Message)
            .where(Message.conversation_id.in_(conv_ids))
            .distinct(Message.conversation_id)
            .order_by(Message.conversation_id, Message.created_at.desc(), Message.id.desc())
        )
    ).scalars().all()
    latest_map = {m.conversation_id: m for m in latest}

    # Partner profiles (the other active member of each DM / staff_dm conversation).
    partner_style_ids = [c.id for c in conversations if c.kind in _PARTNER_KINDS]
    partner_of: dict[UUID, UUID] = {}
    if partner_style_ids:
        for cid, uid in (
            await db.execute(
                select(ConversationMember.conversation_id, ConversationMember.user_id).where(
                    ConversationMember.conversation_id.in_(partner_style_ids),
                    ConversationMember.user_id != user_id,
                )
            )
        ).all():
            partner_of[cid] = uid
    profiles = {
        p.user_id: p
        for p in (
            await db.execute(
                select(Profile).options(*profile_load_options()).where(Profile.user_id.in_(partner_of.values()))
            )
        ).scalars().all()
    } if partner_of else {}
    # Verified campus position, if any — surfaced so a student can see *who* a staff
    # partner is (title/department), not just a name.
    positions = {
        p.user_id: p
        for p in (
            await db.execute(
                select(CampusPosition).where(
                    CampusPosition.user_id.in_(partner_of.values()),
                    CampusPosition.is_primary.is_(True),
                    CampusPosition.is_active.is_(True),
                    CampusPosition.status == 'verified',
                )
            )
        ).scalars().all()
    } if partner_of else {}

    # Group metadata.
    group_ids = [c.id for c in conversations if c.kind == 'group']
    group_of = {
        g.conversation_id: g
        for g in (
            (await db.execute(select(Group).where(Group.conversation_id.in_(group_ids)))).scalars().all()
            if group_ids else []
        )
    }

    threads: list[MessageThreadRead] = []
    for conv in conversations:
        latest_msg = latest_map.get(conv.id)
        if conv.kind in _PARTNER_KINDS:
            partner_profile = profiles.get(partner_of.get(conv.id))
            if partner_profile is None:
                continue  # orphaned conversation (partner profile missing) — skip, as before
            position = positions.get(partner_of.get(conv.id))
            threads.append(MessageThreadRead(
                conversation_id=conv.id, kind=conv.kind, match_id=conv.match_id,
                partner=profile_to_public(partner_profile),
                partner_position_title=position.official_title if position else None,
                partner_department=position.department if position else None,
                latest_message=message_read(latest_msg) if latest_msg else None,
                latest_reaction=reaction_previews.get(conv.id),
                muted=conv.id in muted_ids,
            ))
        else:
            group = group_of.get(conv.id)
            if group is None:
                continue
            threads.append(MessageThreadRead(
                conversation_id=conv.id, kind='group',
                group=GroupThreadInfo(id=group.id, name=group.name, avatar_url=group.avatar_url),
                latest_message=message_read(latest_msg) if latest_msg else None,
                latest_reaction=reaction_previews.get(conv.id),
                muted=conv.id in muted_ids,
            ))

    # Newest activity first; a message beats an empty thread.
    threads.sort(
        key=lambda t: t.latest_message.created_at if t.latest_message else _EPOCH,
        reverse=True,
    )
    return threads
