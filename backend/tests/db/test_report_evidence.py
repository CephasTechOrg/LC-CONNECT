"""Reporting a message snapshots its text (and author) into the report, so moderation evidence
survives the message — or its whole group — being deleted afterwards. Moderation must not be
defeatable by deleting the content."""

from __future__ import annotations

from app.features.groups import service as group_service
from app.features.groups.schema import GroupCreate
from app.features.messages.service import delete_message, persist_message_idempotent
from app.features.safety.schema import ReportCreate
from app.features.safety.service import create_report
from app.models import Conversation


async def _group_with_message(db, factory):
    owner = await factory.user()
    author = await factory.user()
    group = await group_service.create_group(db, owner, GroupCreate(name='Group', category='club', join_policy='open'))
    await group_service.join_group(db, group, author)
    await db.commit()
    msg, _ = await persist_message_idempotent(
        db, sender_id=author.id, match_id=None, conversation_id=group.conversation_id,
        body='offensive content', client_message_id=None,
    )
    await db.commit()
    return owner, author, group, msg


async def test_report_snapshots_body_and_author(db, factory):
    reporter, author, _group, msg = await _group_with_message(db, factory)
    report = await create_report(db, reporter.id, ReportCreate(message_id=msg.id, reason='Harassment'))
    assert report.message_body == 'offensive content'
    assert report.reported_user_id == author.id  # attributed to the message's sender


async def test_evidence_survives_message_soft_delete(db, factory):
    reporter, author, _group, msg = await _group_with_message(db, factory)
    report = await create_report(db, reporter.id, ReportCreate(message_id=msg.id, reason='Spam'))

    await delete_message(db, msg.id, author.id)  # author deletes their message afterwards
    await db.refresh(report)
    assert report.message_body == 'offensive content'  # evidence retained on the report


async def test_evidence_survives_group_hard_delete(db, factory):
    reporter, _author, group, msg = await _group_with_message(db, factory)
    report = await create_report(db, reporter.id, ReportCreate(message_id=msg.id, reason='Hate speech'))

    # Hard-delete the whole group (cascades away the messages) — the classic evidence-destroying move.
    conversation = await db.get(Conversation, group.conversation_id)
    await db.delete(conversation)
    await db.commit()

    await db.refresh(report)
    assert report.message_id is None  # FK SET NULL — the message row is gone
    assert report.message_body == 'offensive content'  # …but the snapshot still holds the evidence
