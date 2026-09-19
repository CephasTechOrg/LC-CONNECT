"""Sent-message editing — report #5 (checklist 3.7).

Editing is the one feature here that can make a message say something it never said, so most of
these are about what it **refuses**: who may edit, for how long, and what survives afterwards.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.config import settings
from app.features.groups import service as group_service
from app.features.groups.schema import GroupCreate
from app.features.messages.editing import edit_message
from app.features.messages.service import delete_message, persist_message_idempotent
from app.models import Conversation, Message, MessageEdit


async def _dm(db, factory, *, body: str = 'original'):
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    conversation_id = (
        await db.execute(select(Conversation.id).where(Conversation.match_id == match.id))
    ).scalar_one()
    message, _ = await persist_message_idempotent(
        db, sender_id=a.id, match_id=match.id, conversation_id=conversation_id,
        body=body, client_message_id=None,
    )
    return a, b, message


# ── the happy path, and its audit trail ──────────────────────────────────────

async def test_an_edit_replaces_the_body_and_stamps_it(db, factory):
    a, b, message = await _dm(db, factory)

    edited = await edit_message(db, message.id, a.id, 'corrected')

    assert edited.body == 'corrected'
    assert edited.edited_at is not None


async def test_the_previous_body_is_kept(db, factory):
    """The audit trail is why editing is allowed at all. Without it an edit destroys evidence —
    which this codebase already refuses to do for deletes and safety reports."""
    a, b, message = await _dm(db, factory, body='the original wording')

    await edit_message(db, message.id, a.id, 'the new wording')

    history = (await db.execute(select(MessageEdit))).scalars().all()
    assert len(history) == 1
    assert history[0].previous_body == 'the original wording'
    assert history[0].message_id == message.id


async def test_each_edit_adds_a_row(db, factory):
    a, b, message = await _dm(db, factory, body='v1')

    await edit_message(db, message.id, a.id, 'v2')
    await edit_message(db, message.id, a.id, 'v3')

    bodies = (await db.execute(select(MessageEdit.previous_body))).scalars().all()
    assert bodies == ['v1', 'v2']


async def test_an_unchanged_body_writes_no_history(db, factory):
    """Otherwise the trail fills with rows saying "X became X" — noise that makes the real edits
    harder to find."""
    a, b, message = await _dm(db, factory, body='same')

    await edit_message(db, message.id, a.id, 'same')

    assert (await db.execute(select(MessageEdit))).scalars().all() == []


async def test_whitespace_is_trimmed_before_comparing(db, factory):
    a, b, message = await _dm(db, factory, body='same')

    await edit_message(db, message.id, a.id, '  same  ')

    assert (await db.execute(select(MessageEdit))).scalars().all() == []


# ── who may edit ─────────────────────────────────────────────────────────────

async def test_only_the_sender_may_edit(db, factory):
    a, b, message = await _dm(db, factory)

    with pytest.raises(HTTPException) as exc:
        await edit_message(db, message.id, b.id, 'not mine to change')
    # 404, not 403: a non-sender should not learn a message exists and is merely un-editable.
    assert exc.value.status_code == 404


async def test_a_group_admin_may_not_edit_someone_elses_message(db, factory):
    """The asymmetry with delete, and the reason for it.

    An admin may *remove* a member's message — moderation needs that. An admin able to **edit**
    one would hold a forgery primitive: putting words in someone's mouth, under their name, in a
    conversation other people are reading. Removing it already does the moderation job.
    """
    owner = await factory.user(display_name='Owner')
    member = await factory.user(display_name='Member')
    group = await group_service.create_group(
        db, owner, GroupCreate(name='CS Club', category='club', visibility='public',
                               join_policy='open')
    )
    await group_service.join_group(db, group, member)
    await db.commit()
    message, _ = await persist_message_idempotent(
        db, sender_id=member.id, match_id=None, conversation_id=group.conversation_id,
        body='what the member said', client_message_id=None,
    )

    with pytest.raises(HTTPException) as exc:
        await edit_message(db, message.id, owner.id, 'what the admin wishes they said')
    assert exc.value.status_code == 404

    unchanged = await db.get(Message, message.id)
    assert unchanged.body == 'what the member said'


async def test_a_non_member_cannot_edit(db, factory):
    a, b, message = await _dm(db, factory)
    outsider = await factory.user(display_name='Outsider')

    with pytest.raises(HTTPException) as exc:
        await edit_message(db, message.id, outsider.id, 'hello')
    assert exc.value.status_code == 404


# ── the window ───────────────────────────────────────────────────────────────

async def test_an_edit_past_the_window_is_refused(db, factory, monkeypatch):
    a, b, message = await _dm(db, factory)
    # Age the message past the window rather than waiting fifteen minutes.
    message.created_at = datetime.now(UTC) - timedelta(
        seconds=settings.message_edit_window_seconds + 60
    )
    await db.commit()

    with pytest.raises(HTTPException) as exc:
        await edit_message(db, message.id, a.id, 'too late')
    assert exc.value.status_code == 409
    # Machine-readable, so the client can say "the edit window has passed" rather than a generic
    # failure — the mistake report #8 made with attendance.
    assert exc.value.detail == 'edit_window_expired'


async def test_the_window_is_generous_enough_to_never_race_a_send_retry(db):
    """The client marks a send failed after 60s. If the edit window were shorter than that, a
    message could become un-editable before the user even knew it had sent."""
    assert settings.message_edit_window_seconds > 60


# ── interaction with delete ──────────────────────────────────────────────────

async def test_editing_a_deleted_message_is_refused(db, factory):
    """Delete wins. Editing a tombstone would resurrect a body the delete exists to withhold —
    the body is never sent to clients once deleted."""
    a, b, message = await _dm(db, factory)
    await delete_message(db, message.id, a.id)

    with pytest.raises(HTTPException) as exc:
        await edit_message(db, message.id, a.id, 'sneaking this back in')
    assert exc.value.status_code == 409


async def test_deleting_an_edited_message_keeps_its_history(db, factory):
    """A soft delete keeps the row, so the edit trail survives with it — which is exactly what
    moderation needs when the question is what a message used to say."""
    a, b, message = await _dm(db, factory, body='first')
    await edit_message(db, message.id, a.id, 'second')

    await delete_message(db, message.id, a.id)

    history = (await db.execute(select(MessageEdit))).scalars().all()
    assert len(history) == 1
    assert history[0].previous_body == 'first'


# ── validation ───────────────────────────────────────────────────────────────

async def test_an_empty_edit_is_refused(db, factory):
    a, b, message = await _dm(db, factory)

    with pytest.raises(HTTPException) as exc:
        await edit_message(db, message.id, a.id, '   ')
    assert exc.value.status_code == 422


async def test_an_oversized_edit_is_refused(db, factory):
    # An edit must not smuggle in a longer message than sending allows.
    from app.shared.message_limits import MAX_BODY_CHARS

    a, b, message = await _dm(db, factory)

    with pytest.raises(HTTPException) as exc:
        await edit_message(db, message.id, a.id, 'x' * (MAX_BODY_CHARS + 1))
    assert exc.value.status_code == 422


async def test_editing_an_unknown_message_is_404(db, factory):
    from uuid import uuid4

    a = await factory.user(display_name='A')
    with pytest.raises(HTTPException) as exc:
        await edit_message(db, uuid4(), a.id, 'hello')
    assert exc.value.status_code == 404


# ── retention ────────────────────────────────────────────────────────────────

async def test_old_edit_history_is_purged_even_when_the_message_lives(db, factory):
    """The case the foreign key does not cover.

    Purging a deleted message cascades its history away. A message that was *edited and never
    deleted* has no such trigger, so without this pass its history would outlive the retention
    window forever — an audit trail with a purpose becoming a permanent record of every rephrase.
    """
    from app.shared.message_retention import purge_soft_deleted_messages

    a, b, message = await _dm(db, factory, body='first')
    await edit_message(db, message.id, a.id, 'second')

    # Age the history past the window.
    history = (await db.execute(select(MessageEdit))).scalars().one()
    history.edited_at = datetime.now(UTC) - timedelta(days=120)
    await db.commit()

    report = await purge_soft_deleted_messages(db, retention_days=90, apply=True)

    assert report.edits_purged == 1
    assert (await db.execute(select(MessageEdit))).scalars().all() == []
    # The message itself is untouched — it was never deleted.
    assert await db.get(Message, message.id) is not None


async def test_recent_edit_history_survives_a_purge(db, factory):
    from app.shared.message_retention import purge_soft_deleted_messages

    a, b, message = await _dm(db, factory, body='first')
    await edit_message(db, message.id, a.id, 'second')

    report = await purge_soft_deleted_messages(db, retention_days=90, apply=True)

    assert report.edits_purged == 0
    assert len((await db.execute(select(MessageEdit))).scalars().all()) == 1


async def test_a_dry_run_purges_nothing(db, factory):
    from app.shared.message_retention import purge_soft_deleted_messages

    a, b, message = await _dm(db, factory, body='first')
    await edit_message(db, message.id, a.id, 'second')
    history = (await db.execute(select(MessageEdit))).scalars().one()
    history.edited_at = datetime.now(UTC) - timedelta(days=120)
    await db.commit()

    report = await purge_soft_deleted_messages(db, retention_days=90, apply=False)

    assert report.edits_purged == 0
    assert len((await db.execute(select(MessageEdit))).scalars().all()) == 1
