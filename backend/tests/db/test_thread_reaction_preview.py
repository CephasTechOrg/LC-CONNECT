"""The inbox has to show a reaction to your message without opening the chat.

The live `messages.reaction_activity` frame updates an open inbox; `latest_reactions_for_threads`
is the durable half that survives a cold load or a restart. These pin what it surfaces and — just
as important — what it must not: it is scoped to the viewer's *own* messages, reacted to by
*someone else*, and it never moves a row or changes an unread count.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.features.messages.reactions import (
    REACTION_ALLOWLIST,
    latest_reactions_for_threads,
    toggle_reaction,
)
from app.features.messages.service import (
    delete_message,
    list_threads_for_user,
    persist_message_idempotent,
)
from app.models import Conversation, MessageReaction

THUMB = REACTION_ALLOWLIST[0]
HEART = REACTION_ALLOWLIST[1]


async def _dm(db, factory):
    """Two matched users and a message from the first (the eventual reaction's author)."""
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()
    message, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body='hello', client_message_id=None,
    )
    return a, b, conversation_id, message


async def test_a_reaction_to_my_message_surfaces_on_my_inbox_row(db, factory):
    a, b, conversation_id, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    previews = await latest_reactions_for_threads(db, [conversation_id], owner_id=a.id)
    preview = previews[conversation_id]
    assert preview.emoji == THUMB
    assert preview.actor_id == b.id
    assert preview.actor_name == 'B'
    assert preview.message_id == message.id


async def test_my_own_reaction_is_not_surfaced_to_me(db, factory):
    """The feature mirrors the notification: you hear when *someone else* reacts to *your*
    message, never about your own tap."""
    a, b, conversation_id, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=a.id, emoji=THUMB, add=True)

    assert await latest_reactions_for_threads(db, [conversation_id], owner_id=a.id) == {}


async def test_a_reaction_on_the_other_persons_message_belongs_to_them_not_me(db, factory):
    """Scoped to the owner's own messages. A reaction A places on B's message is B's inbox news,
    not A's — otherwise the owner would see their own tap echoed back."""
    a, b, conversation_id, message = await _dm(db, factory)
    reply, _ = await persist_message_idempotent(
        db, sender_id=b.id, match_id=message.match_id, conversation_id=conversation_id,
        body='hi back', client_message_id=None,
    )
    await toggle_reaction(db, message_id=reply.id, user_id=a.id, emoji=THUMB, add=True)

    assert await latest_reactions_for_threads(db, [conversation_id], owner_id=a.id) == {}
    b_previews = await latest_reactions_for_threads(db, [conversation_id], owner_id=b.id)
    assert b_previews[conversation_id].actor_id == a.id


async def test_it_reports_the_most_recent_reaction(db, factory):
    """When several people have reacted, the row shows the latest. `func.now()` is constant within
    a test transaction, so the timestamps are set explicitly to order the rows unambiguously."""
    a, b, conversation_id, message = await _dm(db, factory)
    c = await factory.user(display_name='C')
    now = datetime.now(UTC)
    db.add(MessageReaction(
        message_id=message.id, user_id=b.id, emoji=THUMB, created_at=now - timedelta(minutes=5),
    ))
    db.add(MessageReaction(message_id=message.id, user_id=c.id, emoji=HEART, created_at=now))
    await db.commit()

    preview = (
        await latest_reactions_for_threads(db, [conversation_id], owner_id=a.id)
    )[conversation_id]
    assert preview.emoji == HEART
    assert preview.actor_id == c.id


async def test_a_reaction_on_a_deleted_message_is_not_surfaced(db, factory):
    """A deleted message is a tombstone with no body; a reaction preview hanging off it would
    point at nothing the owner can open."""
    a, b, conversation_id, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)
    await delete_message(db, message.id, a.id)

    assert await latest_reactions_for_threads(db, [conversation_id], owner_id=a.id) == {}


async def test_no_reactions_means_no_preview(db, factory):
    a, b, conversation_id, message = await _dm(db, factory)
    assert await latest_reactions_for_threads(db, [conversation_id], owner_id=a.id) == {}


async def test_an_empty_thread_set_touches_the_database_not_at_all(db):
    assert await latest_reactions_for_threads(db, [], owner_id=None) == {}


async def test_the_thread_list_carries_the_preview_additively(db, factory):
    """The inbox endpoint itself, not just the helper: A's row carries the reaction, and it is
    purely additive — the message that heads the row does not change, and the reactor's own row
    shows nothing."""
    a, b, conversation_id, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    threads = await list_threads_for_user(db, a.id)
    row = next(t for t in threads if t.conversation_id == conversation_id)
    assert row.latest_reaction is not None
    assert row.latest_reaction.emoji == THUMB
    assert row.latest_message.id == message.id

    b_threads = await list_threads_for_user(db, b.id)
    b_row = next(t for t in b_threads if t.conversation_id == conversation_id)
    assert b_row.latest_reaction is None
