"""Replying to a message: check what is being replied to, and quote it.

Shared by the REST send endpoint and the WebSocket gateway, so both paths accept and reject the
same targets. A module of its own rather than more of `service.py`: a reply only ever *reads*
another message, it never changes the send itself.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import ReplyPreview
from app.models import Message, Profile
from app.shared.message_snippets import snippet


class ReplyTargetError(Exception):
    """The reply target cannot be quoted. `code` is the client-facing reason:
    `reply_target_missing` (gone, or in another conversation) or `reply_target_deleted`."""

    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


async def validate_reply_target(db: AsyncSession, conversation_id: UUID, reply_to_id: UUID) -> Message:
    """The message being replied to, if it may be. Another conversation's message answers the same
    as a missing one, so a reply cannot be used to probe ids outside the chat."""
    target = (await db.execute(select(Message).where(Message.id == reply_to_id))).scalar_one_or_none()
    if target is None or target.conversation_id != conversation_id:
        raise ReplyTargetError('reply_target_missing')
    if target.deleted_at is not None:
        raise ReplyTargetError('reply_target_deleted')
    return target


def preview_of(target: Message, sender_name: str | None) -> ReplyPreview:
    deleted = target.deleted_at is not None
    return ReplyPreview(
        id=target.id,
        sender_id=target.sender_id,
        sender_name=sender_name,
        body_snippet=snippet(target.body, deleted=deleted),
        deleted=deleted,
        edited=target.edited_at is not None,
    )


async def sender_name(db: AsyncSession, user_id: UUID) -> str | None:
    return (
        await db.execute(select(Profile.display_name).where(Profile.user_id == user_id))
    ).scalar_one_or_none()


async def reply_previews_for(db: AsyncSession, messages: list[Message]) -> dict[UUID, ReplyPreview]:
    """Quotes for every reply on a page — **one query**, keyed by the replying message's id.

    A quote shows the target's *current* state: an edit changes the excerpt (marked `edited`), a
    delete turns it into "Original message was deleted". A target purged by retention leaves
    `reply_to_id` null, so that reply simply has no quote.
    """
    target_ids = {m.reply_to_id for m in messages if m.reply_to_id is not None}
    if not target_ids:
        return {}
    rows = (
        await db.execute(
            select(Message, Profile.display_name)
            .outerjoin(Profile, Profile.user_id == Message.sender_id)
            .where(Message.id.in_(target_ids))
        )
    ).all()
    previews = {target.id: preview_of(target, name) for target, name in rows}
    return {
        m.id: previews[m.reply_to_id]
        for m in messages
        if m.reply_to_id is not None and m.reply_to_id in previews
    }
