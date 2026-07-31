"""Admin/moderation domain logic: suspend, reactivate, activity takedown.

`suspend_user` previously had no undo path anywhere in the admin portal — a mis-click or a
wrong-user suspend was permanent. `reactivate_user` closes that gap.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import func, select

from app.features.admin import service
from app.models import Activity, AdminAuditLog


async def test_suspend_user_sets_status_and_disconnects(db, factory):
    user = await factory.user()
    admin = await factory.user(display_name='Admin')

    result = await service.suspend_user(db, user.id, actor_id=admin.id)
    assert result.status == 'suspended'
    assert result.is_active is False

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(AdminAuditLog.action == 'user.suspend', AdminAuditLog.target_id == user.id)
        )
    ).scalar_one()
    assert audit_count == 1


async def test_suspend_unknown_user_404(db):
    with pytest.raises(HTTPException) as exc:
        await service.suspend_user(db, uuid4())
    assert exc.value.status_code == 404


async def test_reactivate_user_restores_status(db, factory):
    user = await factory.user()
    admin = await factory.user(display_name='Admin')
    await service.suspend_user(db, user.id, actor_id=admin.id)

    result = await service.reactivate_user(db, user.id, actor_id=admin.id)
    assert result.status == 'active'
    assert result.is_active is True

    audit_count = (
        await db.execute(
            select(func.count())
            .select_from(AdminAuditLog)
            .where(AdminAuditLog.action == 'user.reactivate', AdminAuditLog.target_id == user.id)
        )
    ).scalar_one()
    assert audit_count == 1


async def test_reactivate_unknown_user_404(db):
    with pytest.raises(HTTPException) as exc:
        await service.reactivate_user(db, uuid4())
    assert exc.value.status_code == 404


async def test_reactivate_non_suspended_user_is_409(db, factory):
    user = await factory.user()
    with pytest.raises(HTTPException) as exc:
        await service.reactivate_user(db, user.id)
    assert exc.value.status_code == 409


async def test_remove_activity_marks_cancelled(db, factory):
    user = await factory.user()
    activity = Activity(
        creator_id=user.id,
        title='Study session',
        description='...',
        category='social',
        location='Library',
        start_time=datetime.now(UTC),
    )
    db.add(activity)
    await db.commit()

    result = await service.remove_activity(db, activity.id)
    assert result.is_cancelled is True


async def test_remove_unknown_activity_404(db):
    with pytest.raises(HTTPException) as exc:
        await service.remove_activity(db, uuid4())
    assert exc.value.status_code == 404
