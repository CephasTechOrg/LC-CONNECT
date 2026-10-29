"""Search message text across the chats a user is in (`GET /messages/search`).

A substring match (ILIKE) over the user's own conversations, newest first: the conversation
filter narrows it to a few thousand rows at campus scale, which needs no text index yet. When it
does, a pg_trgm GIN index on `messages.body` serves this same query unchanged — see
`docs/architecture/data-integrity.md`.
"""

from __future__ import annotations

import re
from datetime import datetime
from uuid import UUID

from sqlalchemy import and_, exists, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.features.messages.schema import MessageSearchHit
from app.models import Block, Conversation, ConversationMember, Group, Message, Profile
from app.shared.policies import open_staff_thread_ids
from app.shared.text_search import like_pattern

_WHITESPACE = re.compile(r'\s+')
_ONE_TO_ONE = ('dm', 'staff_dm')


async def search_messages(
    db: AsyncSession, user_id: UUID, query: str, *, limit: int, before: datetime | None = None
) -> list[MessageSearchHit]:
    me = aliased(ConversationMember)
    other = aliased(ConversationMember)
    # A one-to-one chat with someone blocked either way is hidden from the inbox; its messages
    # must not come back through search either.
    blocked_dm = exists().where(
        other.conversation_id == Message.conversation_id,
        other.user_id != user_id,
        Conversation.kind.in_(_ONE_TO_ONE),
        exists().where(
            or_(
                and_(Block.blocker_id == user_id, Block.blocked_id == other.user_id),
                and_(Block.blocker_id == other.user_id, Block.blocked_id == user_id),
            )
        ),
    )
    stmt = (
        select(Message, Conversation)
        .join(Conversation, Conversation.id == Message.conversation_id)
        .join(me, and_(me.conversation_id == Message.conversation_id, me.user_id == user_id, me.status == 'active'))
        .where(
            Message.deleted_at.is_(None),
            Message.body.ilike(like_pattern(query), escape='\\'),
            ~blocked_dm,
        )
        .order_by(Message.created_at.desc(), Message.id.desc())
        .limit(limit)
    )
    if before is not None:
        stmt = stmt.where(Message.created_at < before)
    rows = (await db.execute(stmt)).all()

    staff_ids = [c.id for _, c in rows if c.kind == 'staff_dm']
    open_staff = await open_staff_thread_ids(db, staff_ids) if staff_ids else set()
    rows = [(m, c) for m, c in rows if c.kind != 'staff_dm' or c.id in open_staff]
    titles = await _titles(db, user_id, [c for _, c in rows])
    return [
        MessageSearchHit(
            message_id=m.id,
            thread_id=c.match_id or c.id,
            kind=c.kind,
            title=titles.get(c.id, ('Chat', None, None))[0],
            avatar_url=titles.get(c.id, ('', None, None))[1],
            group_id=titles.get(c.id, ('', None, None))[2],
            sender_id=m.sender_id,
            snippet=excerpt(m.body, query),
            created_at=m.created_at,
        )
        for m, c in rows
    ]


async def _titles(
    db: AsyncSession, user_id: UUID, conversations: list[Conversation]
) -> dict[UUID, tuple[str, str | None, UUID | None]]:
    """(name, avatar, group id) per conversation: the partner for a one-to-one chat, else the group."""
    ids = {c.id for c in conversations}
    if not ids:
        return {}
    titles: dict[UUID, tuple[str, str | None, UUID | None]] = {}
    for conv_id, name, avatar in (
        await db.execute(
            select(ConversationMember.conversation_id, Profile.display_name, Profile.avatar_url)
            .join(Profile, Profile.user_id == ConversationMember.user_id)
            .where(ConversationMember.conversation_id.in_(ids), ConversationMember.user_id != user_id)
            .join(Conversation, Conversation.id == ConversationMember.conversation_id)
            .where(Conversation.kind.in_(_ONE_TO_ONE))
        )
    ).all():
        titles[conv_id] = (name or 'LC Student', avatar, None)
    for group in (await db.execute(select(Group).where(Group.conversation_id.in_(ids)))).scalars():
        titles[group.conversation_id] = (group.name, group.avatar_url, group.id)
    return titles


def excerpt(body: str, query: str, *, width: int = 110) -> str:
    """The part of `body` around the first match, so the match is visible in a one-line result."""
    text = _WHITESPACE.sub(' ', body).strip()
    at = text.lower().find(query.lower())
    if at < 0 or len(text) <= width:
        return text[:width] + ('…' if len(text) > width else '')
    start = max(0, at - width // 3)
    end = min(len(text), start + width)
    return ('…' if start > 0 else '') + text[start:end].strip() + ('…' if end < len(text) else '')
