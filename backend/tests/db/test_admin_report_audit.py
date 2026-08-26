"""Admin report view/resolve + suspension reason on the audit trail."""

from __future__ import annotations

import json
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.features.admin import service
from app.models import AdminAuditLog, Report


async def test_suspend_persists_reason_on_audit(db, factory):
    user = await factory.user()
    admin = await factory.user(display_name='Admin')

    await service.suspend_user(db, user.id, actor_id=admin.id, reason='Harassment via DM')

    entry = (
        await db.execute(
            select(AdminAuditLog).where(
                AdminAuditLog.action == 'user.suspend',
                AdminAuditLog.target_id == user.id,
            )
        )
    ).scalar_one()
    after = json.loads(entry.after_data or '{}')
    assert after['reason'] == 'Harassment via DM'
    assert after['status'] == 'suspended'


async def test_report_view_writes_audit(db, factory):
    reporter = await factory.user()
    admin = await factory.user(display_name='Admin')
    report = Report(reporter_id=reporter.id, reason='spam', status='open')
    db.add(report)
    await db.commit()
    await db.refresh(report)

    loaded = await service.get_report_for_moderation(db, report.id, actor_id=admin.id)
    assert loaded.id == report.id

    entry = (
        await db.execute(
            select(AdminAuditLog).where(
                AdminAuditLog.action == 'report.view',
                AdminAuditLog.target_id == report.id,
            )
        )
    ).scalar_one()
    assert entry.actor_id == admin.id


async def test_report_view_unknown_404(db, factory):
    admin = await factory.user(display_name='Admin')
    with pytest.raises(HTTPException) as exc:
        await service.get_report_for_moderation(db, uuid4(), actor_id=admin.id)
    assert exc.value.status_code == 404


async def test_resolve_report_writes_audit(db, factory):
    reporter = await factory.user()
    admin = await factory.user(display_name='Admin')
    report = Report(reporter_id=reporter.id, reason='spam', status='open')
    db.add(report)
    await db.commit()
    await db.refresh(report)

    resolved = await service.resolve_report(
        db, report.id, actor_id=admin.id, note='Warned user; no further action'
    )
    assert resolved.status == 'resolved'

    entry = (
        await db.execute(
            select(AdminAuditLog).where(
                AdminAuditLog.action == 'report.resolve',
                AdminAuditLog.target_id == report.id,
            )
        )
    ).scalar_one()
    after = json.loads(entry.after_data or '{}')
    assert after['status'] == 'resolved'
    assert after['note'] == 'Warned user; no further action'


async def test_resolve_already_resolved_is_409(db, factory):
    reporter = await factory.user()
    admin = await factory.user(display_name='Admin')
    report = Report(reporter_id=reporter.id, reason='spam', status='resolved')
    db.add(report)
    await db.commit()
    await db.refresh(report)

    with pytest.raises(HTTPException) as exc:
        await service.resolve_report(db, report.id, actor_id=admin.id)
    assert exc.value.status_code == 409
