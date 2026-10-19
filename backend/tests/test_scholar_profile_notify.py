"""Honors review decisions must notify the scholar (in-app + email)."""

from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.features.admin import scholar_profiles_router as router


@pytest.mark.asyncio
async def test_notify_scholar_decision_emits_and_emails(monkeypatch):
    emitted: list[dict] = []
    emailed: list[tuple] = []

    async def fake_emit(**kwargs):
        emitted.append(kwargs)

    def fake_quietly(fn, *args, **kwargs):
        emailed.append((fn.__name__, args, kwargs))
        return True

    monkeypatch.setattr(router, 'emit_notification', fake_emit)
    monkeypatch.setattr(router, 'send_quietly', fake_quietly)

    profile_id = uuid4()
    user_id = uuid4()
    await router._notify_scholar_decision(
        user_id=user_id,
        email='scholar@students.livingstone.edu',
        profile_id=profile_id,
        outcome='changes_requested',
        review_note='Please expand the summary.',
    )

    assert emitted == [
        {
            'user_id': user_id,
            'notif_type': 'scholar_profile_changes_requested',
            'target_type': 'scholar_profile',
            'target_id': profile_id,
        }
    ]
    assert emailed[0][0] == 'send_scholar_profile_decision_email'
    assert emailed[0][1][0] == 'scholar@students.livingstone.edu'
    assert emailed[0][2]['outcome'] == 'changes_requested'
    assert emailed[0][2]['review_note'] == 'Please expand the summary.'


@pytest.mark.asyncio
async def test_approve_route_notifies(monkeypatch):
    """Router wiring — approve calls notify after the service commits."""
    profile_id = uuid4()
    user_id = uuid4()
    profile = SimpleNamespace(
        id=profile_id,
        user_id=user_id,
        review_note=None,
        review_status='approved',
    )
    user = SimpleNamespace(email='scholar@students.livingstone.edu')
    social = SimpleNamespace(display_name='Alex')
    notified: list[str] = []

    async def fake_approve(db, *, actor, profile_id):  # noqa: ARG001
        return profile

    async def fake_user_and_profile(db, uid):  # noqa: ARG001
        return user, social

    async def fake_notify(**kwargs):
        notified.append(kwargs['outcome'])

    monkeypatch.setattr(router.scholar_profiles_admin, 'approve_profile', fake_approve)
    monkeypatch.setattr(router, '_user_and_profile', fake_user_and_profile)
    monkeypatch.setattr(router, '_notify_scholar_decision', fake_notify)
    monkeypatch.setattr(
        router,
        '_admin_read',
        lambda p, u, s: SimpleNamespace(id=p.id, review_status=p.review_status),
    )

    result = await router.approve_scholar_profile(
        profile_id=profile_id,
        actor=SimpleNamespace(id=uuid4()),
        db=SimpleNamespace(),
    )
    assert notified == ['approved']
    assert result.review_status == 'approved'
