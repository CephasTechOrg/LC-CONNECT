"""Reacting to a message, end to end: record it, fan it out, notify or retract.

Lives here rather than in the router so the endpoints stay thin, and rather than in
`reactions.py`, which is the data layer and has no business knowing about broadcasts or pushes.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.messages.reactions import (
    ReactionChange,
    clear_reaction,
    reaction_counts,
    set_reaction,
    summaries_for_actor,
)
from app.features.messages.schema import ReactionState
from app.models import MessageReaction, Profile
from app.shared.conversations import active_members_with_mute


async def apply_reaction(
    db: AsyncSession, *, message_id: UUID, actor_id: UUID, emoji: str, add: bool
) -> ReactionState:
    """Set (`add`) or clear the caller's reaction and return the message's resulting state.

    Fans out and notifies only when something changed, so a repeated tap costs one query and
    sends nothing. The returned state is what the client reconciles its optimistic chips with.
    """
    if add:
        change = await set_reaction(db, message_id=message_id, user_id=actor_id, emoji=emoji)
        mine = emoji
    else:
        change = await clear_reaction(db, message_id=message_id, user_id=actor_id, emoji=emoji)
        mine = None if change.changed else await _my_emoji(db, message_id, actor_id)

    counts = await reaction_counts(db, message_id)
    if change.changed:
        await _fan_out(db, change, message_id=message_id, actor_id=actor_id, counts=counts)
    return ReactionState(message_id=message_id, reactions=summaries_for_actor(counts, mine=mine))


async def _my_emoji(db: AsyncSession, message_id: UUID, user_id: UUID) -> str | None:
    return (
        await db.execute(
            select(MessageReaction.emoji).where(
                MessageReaction.message_id == message_id, MessageReaction.user_id == user_id
            )
        )
    ).scalar_one_or_none()


async def _fan_out(
    db: AsyncSession, change: ReactionChange, *, message_id: UUID, actor_id: UUID, counts: list
) -> None:
    from app.features.realtime.broadcasts import broadcast_reaction_change, retract_notification
    from app.features.realtime.runtime import emit_notification, emit_reaction_activity

    reacted = change.message
    members = await active_members_with_mute(db, reacted.conversation_id)
    actor_name = (
        await db.execute(select(Profile.display_name).where(Profile.user_id == actor_id))
    ).scalar_one_or_none()

    await broadcast_reaction_change(
        addressing_id=reacted.addressing_id,
        message_id=message_id,
        actor_id=actor_id,
        actor_name=actor_name,
        previous=change.previous,
        current=change.current,
        counts=[c.model_dump(include={'emoji', 'count'}) for c in counts],
        message_sender_id=reacted.sender_id,
        message_snippet=reacted.snippet,
        member_ids=[uid for uid, _ in members],
    )

    # The author hears about reactions to their own message — nobody else, and not themselves.
    sender = reacted.sender_id
    if sender is None or sender == actor_id:
        return
    if change.current is None:
        # Un-reacted: take back the notification if it has not been seen yet.
        await retract_notification(
            user_id=sender, notif_type='message_reaction', actor_id=actor_id, subject_id=message_id
        )
        return

    # The v4 inbox signal, kept for clients that predate the state frame above.
    await emit_reaction_activity(
        sender_id=sender,
        actor_id=actor_id,
        addressing_id=reacted.addressing_id,
        message_id=message_id,
        emoji=change.current,
    )
    sender_muted = any(uid == sender and muted for uid, muted in members)
    target_type = 'group_chat' if reacted.is_group else 'dm'
    await emit_notification(
        user_id=sender,
        notif_type='message_reaction',
        actor_id=actor_id,
        # The *type* says which chat route to open, so the client never has to infer it from a
        # thread list it may not have loaded yet.
        target_type=target_type,
        target_id=reacted.addressing_id,
        subject_id=message_id,
        detail=change.current,
        collapse_unread=True,
        # Muted chat: the row still appears in the inbox, but no push interrupts.
        push=not sender_muted,
        push_data={'target_type': target_type, 'conversation_id': str(reacted.addressing_id)},
    )
