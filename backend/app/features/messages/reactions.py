"""Message reactions — report #4.

Split out of `service.py` when that file crossed the 600-line hard cap. The seam is real rather
than arbitrary: everything here is about one small side table, and none of it is on the send or
read path that the rest of the service exists to serve.

One reaction per person per message, as in WhatsApp: setting an emoji replaces the caller's
previous one. `set_reaction` and `clear_reaction` report whether anything actually changed, so
the caller fans out and notifies only on a real change — a duplicate tap used to broadcast anyway,
and clients applying it as a +1 drifted.
"""

from __future__ import annotations

from typing import NamedTuple
from uuid import UUID, uuid4

from fastapi import HTTPException, status
from sqlalchemy import and_, delete, func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import MessageReactor, ReactionSummary, ThreadReactionPreview
from app.models import Conversation, Message, MessageReaction, Profile
from app.shared.message_snippets import snippet

#: The reactions a client may send, in the order the picker shows them.
#:
#: Six, each a distinct intent with no overlap: agree, love, funny, surprise, sad, thanks. Bounded
#: rather than free text for three reasons — it caps what the per-message aggregate can return, it
#: keeps arbitrary payloads out of a column that renders straight into the UI, and it means the
#: chip strip has a known maximum width. An enum table would have cost a join on the hottest read
#: in the app. Kept equal to the app's picker by `tests/test_reaction_allowlist_parity.py`.
#:
#: Adding one is a one-line change here; removing one leaves existing rows readable but
#: un-addable, which is the right way round (👏 and 🔥 were removed that way).
REACTION_ALLOWLIST: tuple[str, ...] = ('👍', '❤️', '😂', '😮', '😢', '🙏')


class ReactedMessage(NamedTuple):
    """Who and where the caller just reacted to — everything the fan-out needs, resolved once."""

    conversation_id: UUID
    sender_id: UUID | None
    #: The id *clients* address this conversation by — a DM's match id, or the conversation id for
    #: a group, which has none. Mirrors `protocol.addressing_id`. A notification routed on the
    #: canonical id would open nothing for a DM, which is the bug `openMessageConversation` had.
    addressing_id: UUID
    is_group: bool
    #: A one-line excerpt of the reacted message, for previews and notifications.
    snippet: str = ''


class ReactionChange(NamedTuple):
    """What a set or clear did. `changed` is false for a no-op (same emoji again, nothing to
    remove), and then nothing should be broadcast or notified."""

    message: ReactedMessage
    previous: str | None
    current: str | None
    changed: bool


async def _resolve(db: AsyncSession, message_id: UUID, user_id: UUID) -> ReactedMessage:
    """Load the message and authorize the caller. Membership is checked *before* the deleted
    check: the other order answers "does this message exist and was it deleted?" to anyone holding
    the id — a 409 where a stranger should see the same 404 a non-existent id gives."""
    row = (
        await db.execute(
            select(
                Message.conversation_id,
                Message.deleted_at,
                Message.sender_id,
                Message.match_id,
                Message.body,
            ).where(Message.id == message_id)
        )
    ).one_or_none()
    if row is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')
    conversation_id, deleted_at, sender_id, match_id, body = row

    from app.shared.conversations import accessible_conversation

    await accessible_conversation(db, conversation_id, user_id)
    # Reacting to a deleted message is refused: its body is never sent to clients, so a reaction
    # would be attached to a tombstone nobody can read.
    if deleted_at is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='That message was deleted')
    return ReactedMessage(
        conversation_id, sender_id, match_id or conversation_id, match_id is None, snippet(body)
    )


def _check_allowed(emoji: str) -> None:
    if emoji not in REACTION_ALLOWLIST:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail='That reaction is not available',
        )


async def set_reaction(
    db: AsyncSession, *, message_id: UUID, user_id: UUID, emoji: str
) -> ReactionChange:
    """Make `emoji` the caller's one reaction to the message, replacing any other.

    An upsert on `uq_message_reaction_user`, so a double-tap or two devices at once still leave
    exactly one row. The previous emoji is read under a row lock first, so the caller can tell a
    replace (notify with the new emoji) from a repeat (do nothing).
    """
    _check_allowed(emoji)
    resolved = await _resolve(db, message_id, user_id)
    previous = (
        await db.execute(
            select(MessageReaction.emoji)
            .where(MessageReaction.message_id == message_id, MessageReaction.user_id == user_id)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if previous == emoji:
        # Release the row lock. A commit rather than a rollback: nothing was written either way,
        # and a rollback would expire every object the caller still holds from this session.
        await db.commit()
        return ReactionChange(resolved, previous, emoji, changed=False)

    await db.execute(
        pg_insert(MessageReaction)
        .values(id=uuid4(), message_id=message_id, user_id=user_id, emoji=emoji)
        .on_conflict_do_update(
            constraint='uq_message_reaction_user',
            set_={'emoji': emoji, 'created_at': func.now()},
        )
    )
    await db.commit()
    return ReactionChange(resolved, previous, emoji, changed=True)


async def clear_reaction(
    db: AsyncSession, *, message_id: UUID, user_id: UUID, emoji: str
) -> ReactionChange:
    """Remove the caller's reaction if it is `emoji`. Matching on the emoji means a stale client
    removing 👍 cannot take away the ❤️ the same person picked since on another device."""
    resolved = await _resolve(db, message_id, user_id)
    removed = (
        await db.execute(
            delete(MessageReaction)
            .where(
                MessageReaction.message_id == message_id,
                MessageReaction.user_id == user_id,
                MessageReaction.emoji == emoji,
            )
            .returning(MessageReaction.emoji)
        )
    ).scalar_one_or_none()
    await db.commit()
    return ReactionChange(resolved, removed, None, changed=removed is not None)


async def toggle_reaction(
    db: AsyncSession, *, message_id: UUID, user_id: UUID, emoji: str, add: bool
) -> ReactedMessage:
    """Set or clear, for callers that only need the resolved message (tests, older paths)."""
    if add:
        return (await set_reaction(db, message_id=message_id, user_id=user_id, emoji=emoji)).message
    return (await clear_reaction(db, message_id=message_id, user_id=user_id, emoji=emoji)).message


async def reactions_for(
    db: AsyncSession, message_ids: list[UUID], *, viewer_id: UUID
) -> dict[UUID, list[ReactionSummary]]:
    """Aggregated reactions for a page of messages — **one query, never one per message**.

    With the API and the database in the same region a round trip is a few milliseconds, but a
    per-message query over a 50-row page is fifty of them; before the regions were co-located that
    was about three seconds. `bool_or(user_id = viewer)` answers "did I react" in the same pass
    rather than needing a second query.
    """
    if not message_ids:
        return {}

    rows = (
        await db.execute(
            select(
                MessageReaction.message_id,
                MessageReaction.emoji,
                func.count(MessageReaction.id),
                func.bool_or(MessageReaction.user_id == viewer_id),
            )
            .where(MessageReaction.message_id.in_(message_ids))
            .group_by(MessageReaction.message_id, MessageReaction.emoji)
        )
    ).all()

    summaries: dict[UUID, list[ReactionSummary]] = {}
    for message_id, emoji, count, mine in rows:
        summaries.setdefault(message_id, []).append(
            ReactionSummary(emoji=emoji, count=count, reacted_by_me=bool(mine))
        )
    for items in summaries.values():
        sort_by_picker(items)
    return summaries


def sort_by_picker(items: list[ReactionSummary]) -> None:
    """Stable order, matching the picker, so a chip strip does not reshuffle between requests.
    Emoji no longer in the picker sort last."""
    order = {emoji: index for index, emoji in enumerate(REACTION_ALLOWLIST)}
    items.sort(key=lambda s: order.get(s.emoji, len(order)))


async def reactors_for(db: AsyncSession, message_id: UUID, viewer_id: UUID) -> list[MessageReactor]:
    """Who reacted to a message and with what, newest first — the "Reacted by" sheet.

    Same gate as `read_by`: a member of the conversation, or the same 404 a stranger gets for a
    message that does not exist. Includes the viewer.
    """
    conversation_id = (
        await db.execute(select(Message.conversation_id).where(Message.id == message_id))
    ).scalar_one_or_none()
    if conversation_id is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')

    from app.shared.conversations import accessible_conversation

    await accessible_conversation(db, conversation_id, viewer_id)
    rows = (
        await db.execute(
            select(
                MessageReaction.user_id,
                Profile.display_name,
                Profile.avatar_url,
                MessageReaction.emoji,
                MessageReaction.created_at,
            )
            .outerjoin(Profile, Profile.user_id == MessageReaction.user_id)
            .where(MessageReaction.message_id == message_id)
            .order_by(MessageReaction.created_at.desc(), MessageReaction.id.desc())
        )
    ).all()
    return [
        MessageReactor(user_id=uid, display_name=name, avatar_url=avatar, emoji=emoji, reacted_at=at)
        for uid, name, avatar, emoji, at in rows
    ]


async def latest_reactions_for_threads(
    db: AsyncSession, conversation_ids: list[UUID], *, owner_id: UUID
) -> dict[UUID, ThreadReactionPreview]:
    """The newest reaction worth showing on each inbox row — **one bounded query** for the whole
    inbox (``DISTINCT ON`` the conversation).

    In a DM, any reaction (both people are in it). In a group, only a reaction to `owner_id`'s own
    message or one `owner_id` left: everyone else's reactions to everyone else's messages would
    otherwise take over a busy group's row. Reactions to deleted messages are skipped.

    No ordering or unread implications: the caller attaches the result to a row it has already
    placed, and shows it only when it is newer than the row's latest message.
    """
    if not conversation_ids:
        return {}

    relevant = or_(
        Conversation.kind != 'group',
        Message.sender_id == owner_id,
        MessageReaction.user_id == owner_id,
    )
    rows = (
        await db.execute(
            select(
                Message.conversation_id,
                MessageReaction.emoji,
                MessageReaction.user_id,
                MessageReaction.message_id,
                MessageReaction.created_at,
                Profile.display_name,
                Message.sender_id,
                Message.body,
            )
            .select_from(MessageReaction)
            .join(Message, Message.id == MessageReaction.message_id)
            .join(Conversation, Conversation.id == Message.conversation_id)
            .outerjoin(Profile, Profile.user_id == MessageReaction.user_id)
            .where(
                and_(
                    Message.conversation_id.in_(conversation_ids),
                    Message.deleted_at.is_(None),
                    relevant,
                )
            )
            # Latest reaction per conversation. Mirrors the `DISTINCT ON` the thread list already
            # uses for the latest message, so it stays one query rather than one per thread.
            .distinct(Message.conversation_id)
            .order_by(
                Message.conversation_id,
                MessageReaction.created_at.desc(),
                MessageReaction.id.desc(),
            )
        )
    ).all()

    return {
        conversation_id: ThreadReactionPreview(
            emoji=emoji,
            actor_id=actor_id,
            actor_name=display_name,
            message_id=message_id,
            reacted_at=created_at,
            message_sender_id=sender_id,
            message_snippet=snippet(body),
        )
        for conversation_id, emoji, actor_id, message_id, created_at, display_name, sender_id, body in rows
    }


def summaries_for_actor(
    counts: list[ReactionSummary], *, mine: str | None
) -> list[ReactionSummary]:
    """Viewer-neutral counts re-flagged from one person's point of view."""
    return [
        ReactionSummary(emoji=c.emoji, count=c.count, reacted_by_me=c.emoji == mine) for c in counts
    ]


async def reaction_counts(db: AsyncSession, message_id: UUID) -> list[ReactionSummary]:
    """One message's tallies with no viewer (`reacted_by_me` false), for the fan-out frame."""
    rows = (
        await db.execute(
            select(MessageReaction.emoji, func.count(MessageReaction.id))
            .where(MessageReaction.message_id == message_id)
            .group_by(MessageReaction.emoji)
        )
    ).all()
    items = [ReactionSummary(emoji=e, count=n, reacted_by_me=False) for e, n in rows]
    sort_by_picker(items)
    return items

