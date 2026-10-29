"""The inbox has to show a reaction to your message without opening the chat.

The live reaction frame updates an open inbox; `latest_reactions_for_threads` is the durable half
that survives a cold load or a restart. In a DM it is any reaction (so the row can say "You reacted
❤️ to …" as well as "Ama reacted 👍 to …"); in a group only one to or by the viewer. It never moves
a row or changes an unread count.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.features.messages.reactions import (
    REACTION_ALLOWLIST,
    latest_reactions_for_threads,
    toggle_reaction,
)
from app.features.messages.service import delete_message, persist_message_idempotent
from app.features.messages.threads import list_threads_for_user
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


async def test_my_own_reaction_shows_on_my_dm_row(db, factory):
    """"You reacted 👍 to “hello”", as WhatsApp shows it — the row reflects the last thing that
    happened in the chat, whoever did it."""
    a, b, conversation_id, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=a.id, emoji=THUMB, add=True)

    preview = (await latest_reactions_for_threads(db, [conversation_id], owner_id=a.id))[conversation_id]
    assert preview.actor_id == a.id
    assert preview.message_sender_id == a.id
    assert preview.message_snippet == 'hello'


async def test_a_dm_reaction_shows_on_both_rows(db, factory):
    a, b, conversation_id, message = await _dm(db, factory)
    reply, _ = await persist_message_idempotent(
        db, sender_id=b.id, match_id=message.match_id, conversation_id=conversation_id,
        body='hi back', client_message_id=None,
    )
    await toggle_reaction(db, message_id=reply.id, user_id=a.id, emoji=THUMB, add=True)

    for owner in (a, b):
        preview = (await latest_reactions_for_threads(db, [conversation_id], owner_id=owner.id))[conversation_id]
        assert (preview.actor_id, preview.message_snippet) == (a.id, 'hi back')


async def test_a_group_row_shows_only_reactions_to_or_by_me(db, factory):
    """Everyone else's reactions to everyone else's messages would otherwise take over a busy
    group's row."""
    from app.features.groups import service as group_service
    from app.features.groups.schema import GroupCreate
    from app.models import ConversationMember

    me = await factory.user(display_name='Me')
    x = await factory.user(display_name='X')
    y = await factory.user(display_name='Y')
    group = await group_service.create_group(
        db, me, GroupCreate(name='Club', category='club', join_policy='open')
    )
    for u in (x, y):
        db.add(ConversationMember(conversation_id=group.conversation_id, user_id=u.id, status='active'))
    await db.commit()
    xs, _ = await persist_message_idempotent(
        db, sender_id=x.id, match_id=None, conversation_id=group.conversation_id,
        body='x says', client_message_id=None,
    )
    await toggle_reaction(db, message_id=xs.id, user_id=y.id, emoji=THUMB, add=True)

    assert await latest_reactions_for_threads(db, [group.conversation_id], owner_id=me.id) == {}
    x_view = await latest_reactions_for_threads(db, [group.conversation_id], owner_id=x.id)
    assert x_view[group.conversation_id].actor_id == y.id


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
    """The inbox endpoint itself, not just the helper: both rows carry the reaction, and it is purely
    additive — the message that heads the row does not change."""
    a, b, conversation_id, message = await _dm(db, factory)
    await toggle_reaction(db, message_id=message.id, user_id=b.id, emoji=THUMB, add=True)

    threads = await list_threads_for_user(db, a.id)
    row = next(t for t in threads if t.conversation_id == conversation_id)
    assert row.latest_reaction is not None
    assert row.latest_reaction.emoji == THUMB
    assert row.latest_message.id == message.id

    b_threads = await list_threads_for_user(db, b.id)
    b_row = next(t for t in b_threads if t.conversation_id == conversation_id)
    assert b_row.latest_reaction is not None and b_row.latest_reaction.actor_id == b.id
    assert b_row.muted is False
