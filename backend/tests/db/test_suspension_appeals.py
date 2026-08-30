"""Suspension appeal workflow (#22) — suspended users can file one open appeal at a time."""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.features.account import suspension as suspension_service
from app.features.admin import service as admin_service
from app.models import SuspensionAppeal


async def test_suspended_user_can_submit_appeal(db, factory):
    user = await factory.user()
    admin = await factory.user(display_name='Admin')
    await admin_service.suspend_user(db, user.id, actor_id=admin.id, reason='Test')

    appeal = await suspension_service.submit_appeal(db, user, message='I believe this was a mistake.')
    assert appeal.status == 'open'
    assert appeal.user_id == user.id


async def test_duplicate_open_appeal_is_409(db, factory):
    user = await factory.user()
    admin = await factory.user(display_name='Admin')
    await admin_service.suspend_user(db, user.id, actor_id=admin.id, reason='Test')
    await suspension_service.submit_appeal(db, user, message='First appeal message here.')

    with pytest.raises(HTTPException) as exc:
        await suspension_service.submit_appeal(db, user, message='Second appeal message here.')
    assert exc.value.status_code == 409


async def test_non_suspended_user_cannot_appeal(db, factory):
    user = await factory.user()
    with pytest.raises(HTTPException) as exc:
        await suspension_service.submit_appeal(db, user, message='Should not be allowed at all.')
    assert exc.value.status_code == 409


async def test_admin_resolve_closes_appeal(db, factory):
    user = await factory.user()
    admin = await factory.user(display_name='Admin')
    await admin_service.suspend_user(db, user.id, actor_id=admin.id, reason='Test')
    appeal = await suspension_service.submit_appeal(db, user, message='Please review my account.')

    closed = await suspension_service.review_appeal(
        db, appeal.id, actor_id=admin.id, new_status='resolved', note='Reviewed — reactivate separately'
    )
    assert closed.status == 'resolved'
    assert closed.admin_note is not None
    assert closed.reviewed_by_id == admin.id


async def test_list_appeals_filters_by_status(db, factory):
    user = await factory.user()
    admin = await factory.user(display_name='Admin')
    await admin_service.suspend_user(db, user.id, actor_id=admin.id, reason='Test')
    await suspension_service.submit_appeal(db, user, message='Open appeal for moderation.')

    open_appeals = await suspension_service.list_appeals(db, status_filter='open')
    assert len(open_appeals) == 1
    assert open_appeals[0].status == 'open'


async def test_review_unknown_appeal_404(db):
    with pytest.raises(HTTPException) as exc:
        await suspension_service.review_appeal(
            db, uuid4(), actor_id=uuid4(), new_status='dismissed', note=None
        )
    assert exc.value.status_code == 404
