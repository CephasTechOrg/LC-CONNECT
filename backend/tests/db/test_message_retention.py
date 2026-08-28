"""Retention purge for soft-deleted messages (cron job logic)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.features.messages.service import delete_message
from app.features.safety.schema import ReportCreate
from app.features.safety.service import create_report
from app.models import Message
from app.shared.message_retention import purge_soft_deleted_messages


async def _soft_delete_old(db, factory, *, days_ago: int) -> Message:
    a = await factory.user(display_name='A')
    b = await factory.user(display_name='B')
    match = await factory.match(a, b)
    msg = await factory.message(match, a, 'old secret')
    await delete_message(db, msg.id, a.id)
    msg.deleted_at = datetime.now(UTC) - timedelta(days=days_ago)
    await db.commit()
    await db.refresh(msg)
    return msg


async def test_dry_run_counts_but_does_not_delete(db, factory):
    msg = await _soft_delete_old(db, factory, days_ago=120)

    report = await purge_soft_deleted_messages(db, retention_days=90, apply=False)

    assert report.eligible == 1
    assert report.purged == 0
    assert msg.id in report.sample_ids
    still = await db.get(Message, msg.id)
    assert still is not None


async def test_apply_deletes_past_retention_window(db, factory):
    old = await _soft_delete_old(db, factory, days_ago=120)
    recent = await _soft_delete_old(db, factory, days_ago=10)

    report = await purge_soft_deleted_messages(db, retention_days=90, apply=True)

    assert report.eligible == 1
    assert report.purged == 1
    assert await db.get(Message, old.id) is None
    assert await db.get(Message, recent.id) is not None


async def test_non_deleted_messages_are_untouched(db, factory):
    a = await factory.user()
    b = await factory.user()
    match = await factory.match(a, b)
    live = await factory.message(match, a, 'still here')
    await db.commit()

    await purge_soft_deleted_messages(db, retention_days=90, apply=True)

    assert await db.get(Message, live.id) is not None


async def test_report_evidence_survives_message_row_purge(db, factory):
    a = await factory.user(display_name='Author')
    b = await factory.user(display_name='Reporter')
    match = await factory.match(a, b)
    msg = await factory.message(match, a, 'reported text')
    report = await create_report(db, b.id, ReportCreate(message_id=msg.id, reason='Harassment'))
    await delete_message(db, msg.id, a.id)
    msg.deleted_at = datetime.now(UTC) - timedelta(days=120)
    await db.commit()

    await purge_soft_deleted_messages(db, retention_days=90, apply=True)

    await db.refresh(report)
    assert report.message_body == 'reported text'
    assert report.message_id is None  # FK set null on hard delete
    assert await db.scalar(select(Message.id).where(Message.id == msg.id)) is None
