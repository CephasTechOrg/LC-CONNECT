"""Replying to a message: what can be quoted, and how the quote reads later.

A reply that silently lost its quote would change what the sender said, so a bad target is an
error on both send paths rather than a quiet drop. A quote shows its target's *current* state —
edited text, or that it was deleted — and a purge leaves the reply standing without one.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import delete, select

from app.features.messages.replies import (
    ReplyTargetError,
    reply_previews_for,
    validate_reply_target,
)
from app.features.messages.router import send_message
from app.features.messages.schema import MessageCreate
from app.features.messages.service import delete_message, persist_message_idempotent
from app.models import Conversation, Message


@pytest.fixture(autouse=True)
def _quiet_fan_out(monkeypatch):
    from app.features.realtime import runtime

    async def nothing(*args, **kwargs):
        return None

    monkeypatch.setattr(runtime.event_bus, 'publish_to_user', nothing)
    monkeypatch.setattr(runtime.event_bus, 'publish_to_conversation', nothing)


async def _dm(db, factory):
    a = await factory.user(display_name='Ama')
    b = await factory.user(display_name='Kofi')
    match = await factory.match(a, b)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()
    original, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body='see you at 5', client_message_id=None,
    )
    return a, b, match, original


async def test_a_reply_carries_a_quote_of_its_target(db, factory):
    a, b, match, original = await _dm(db, factory)
    read = await send_message(
        match.id, MessageCreate(body='on my way', reply_to_id=original.id), current_user=b, db=db
    )
    assert read.reply_to is not None
    assert (read.reply_to.id, read.reply_to.sender_name, read.reply_to.body_snippet) == (
        original.id, 'Ama', 'see you at 5',
    )


async def test_a_message_from_another_chat_cannot_be_quoted(db, factory):
    a, b, match, original = await _dm(db, factory)
    c = await factory.user(display_name='C')
    other = await factory.match(b, c)
    with pytest.raises(HTTPException) as exc:
        await send_message(other.id, MessageCreate(body='x', reply_to_id=original.id), current_user=b, db=db)
    assert (exc.value.status_code, exc.value.detail) == (422, 'reply_target_missing')


async def test_a_deleted_message_cannot_be_quoted(db, factory):
    a, b, match, original = await _dm(db, factory)
    await delete_message(db, original.id, a.id)
    with pytest.raises(HTTPException) as exc:
        await send_message(match.id, MessageCreate(body='x', reply_to_id=original.id), current_user=b, db=db)
    assert (exc.value.status_code, exc.value.detail) == (409, 'reply_target_deleted')


async def test_an_unknown_target_is_missing(db, factory):
    a, b, match, original = await _dm(db, factory)
    with pytest.raises(ReplyTargetError) as exc:
        await validate_reply_target(db, original.conversation_id, uuid4())
    assert exc.value.code == 'reply_target_missing'


async def test_a_quote_follows_its_target_after_an_edit_and_a_delete(db, factory):
    a, b, match, original = await _dm(db, factory)
    reply, _ = await persist_message_idempotent(
        db, sender_id=b.id, match_id=match.id, conversation_id=original.conversation_id,
        body='ok', client_message_id=None, reply_to_id=original.id,
    )
    from app.features.messages.editing import edit_message

    await edit_message(db, original.id, a.id, 'see you at 6')
    quote = (await reply_previews_for(db, [reply]))[reply.id]
    assert (quote.body_snippet, quote.edited, quote.deleted) == ('see you at 6', True, False)

    await delete_message(db, original.id, a.id)
    quote = (await reply_previews_for(db, [reply]))[reply.id]
    assert (quote.body_snippet, quote.deleted) == ('', True)


async def test_a_purged_target_leaves_the_reply_without_a_quote(db, factory):
    a, b, match, original = await _dm(db, factory)
    reply, _ = await persist_message_idempotent(
        db, sender_id=b.id, match_id=match.id, conversation_id=original.conversation_id,
        body='ok', client_message_id=None, reply_to_id=original.id,
    )
    await db.execute(delete(Message).where(Message.id == original.id))
    await db.commit()
    await db.refresh(reply)
    assert reply.reply_to_id is None
    assert await reply_previews_for(db, [reply]) == {}


async def test_a_retried_reply_returns_the_original_quote(db, factory):
    a, b, match, original = await _dm(db, factory)
    key = uuid4()
    first = await send_message(
        match.id, MessageCreate(body='ok', client_message_id=key, reply_to_id=original.id),
        current_user=b, db=db,
    )
    again = await send_message(
        match.id, MessageCreate(body='ok', client_message_id=key, reply_to_id=original.id),
        current_user=b, db=db,
    )
    assert again.id == first.id
    assert again.reply_to is not None and again.reply_to.id == original.id
