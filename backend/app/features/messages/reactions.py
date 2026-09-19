"""Message reactions — report #4.

Split out of `service.py` when that file crossed the 600-line hard cap. The seam is real rather
than arbitrary: everything here is about one small side table, and none of it is on the send or
read path that the rest of the service exists to serve.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.schema import ReactionSummary
from app.models import Message, MessageReaction

#: The reactions a client may send, in the order the picker shows them.
#:
#: Six, each a distinct intent with no overlap: agree, love, funny, surprise, sad, thanks. Bounded
#: rather than free text for three reasons — it caps what the per-message aggregate can return, it
#: keeps arbitrary payloads out of a column that renders straight into the UI, and it means the
#: chip strip has a known maximum width. An enum table would have cost a join on the hottest read
#: in the app.
#:
#: Adding one is a one-line change here; removing one leaves existing rows readable but
#: un-addable, which is the right way round.
REACTION_ALLOWLIST: tuple[str, ...] = ('👍', '❤️', '😂', '😮', '😢', '🙏')


async def toggle_reaction(
    db: AsyncSession, *, message_id: UUID, user_id: UUID, emoji: str, add: bool
) -> UUID:
    """Add or remove one person's one emoji on one message. Idempotent in both directions.

    Authorization is the same gate every other REST message endpoint uses, so a message id alone
    reveals nothing: not-a-member is a 404, blocked or a closed staff thread a 403.

    Reacting to a soft-deleted message is refused. The body of a deleted message is never sent to
    clients, so a reaction on one would be attached to a tombstone nobody can read.

    Returns the conversation the message belongs to, so the caller can fan the change out
    without asking the database the question this function has already answered.
    """
    if emoji not in REACTION_ALLOWLIST:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail='That reaction is not available',
        )

    message = (
        await db.execute(
            select(Message.conversation_id, Message.deleted_at).where(Message.id == message_id)
        )
    ).one_or_none()
    if message is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found')
    conversation_id, deleted_at = message

    from app.shared.conversations import accessible_conversation

    # Membership is checked *before* the deleted check, not after. The other order answers
    # "does this message exist and was it deleted?" to anyone holding the id, including someone
    # with no access to the conversation — a 409 where a stranger should see the same 404 a
    # non-existent id gives. Authorizing first collapses both back into one answer.
    await accessible_conversation(db, conversation_id, user_id)

    if deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail='That message was deleted'
        )

    if not add:
        await db.execute(
            delete(MessageReaction).where(
                MessageReaction.message_id == message_id,
                MessageReaction.user_id == user_id,
                MessageReaction.emoji == emoji,
            )
        )
        await db.commit()
        return conversation_id

    db.add(MessageReaction(message_id=message_id, user_id=user_id, emoji=emoji))
    try:
        await db.commit()
    except IntegrityError:
        # The unique constraint is the arbiter, exactly as in `persist_message_idempotent`: a
        # double-tap, or two devices reacting at once, is success rather than an error. Reporting
        # a conflict here would make the client undo an optimistic chip that is in fact correct.
        await db.rollback()
    return conversation_id


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
    # Stable order, matching the picker, so a chip strip does not reshuffle between requests.
    order = {emoji: index for index, emoji in enumerate(REACTION_ALLOWLIST)}
    for items in summaries.values():
        items.sort(key=lambda s: order.get(s.emoji, len(order)))
    return summaries
