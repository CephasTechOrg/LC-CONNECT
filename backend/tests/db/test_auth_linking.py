"""Tests for auth_user_id linking helper (#25)."""

from __future__ import annotations

from uuid import uuid4

import pytest

from app.models import User
from app.shared.auth_linking import is_live_account, link_existing_auth_users


@pytest.mark.asyncio
async def test_link_matches_supabase_email(db, factory):
    auth_id = uuid4()
    user = await factory.user(display_name='Legacy')
    user.email = 'legacy@students.livingstone.edu'
    user.auth_user_id = None
    await db.commit()

    report = await link_existing_auth_users(
        db,
        lookup_auth_id=lambda email: str(auth_id) if email == user.email else None,
        apply=True,
    )

    assert len(report.linked) == 1
    assert report.ok_for_credential_drop
    await db.refresh(user)
    assert user.auth_user_id == auth_id


@pytest.mark.asyncio
async def test_dry_run_does_not_write(db, factory):
    auth_id = uuid4()
    user = await factory.user(display_name='Dry')
    user.email = 'dry@students.livingstone.edu'
    user.auth_user_id = None
    await db.commit()

    report = await link_existing_auth_users(
        db,
        lookup_auth_id=lambda _e: str(auth_id),
        apply=False,
    )
    assert len(report.linked) == 1
    await db.refresh(user)
    assert user.auth_user_id is None


@pytest.mark.asyncio
async def test_missing_supabase_blocks_gate(db, factory):
    user = await factory.user(display_name='NoAuth')
    user.auth_user_id = None
    await db.commit()

    report = await link_existing_auth_users(
        db,
        lookup_auth_id=lambda _e: None,
        apply=True,
    )
    assert report.missing_in_supabase
    assert not report.ok_for_credential_drop


@pytest.mark.asyncio
async def test_deleted_users_ignored(db, factory):
    from datetime import UTC, datetime

    user = await factory.user(display_name='Gone')
    user.auth_user_id = None
    user.status = 'deleted'
    user.deleted_at = datetime.now(UTC)
    await db.commit()

    report = await link_existing_auth_users(
        db,
        lookup_auth_id=lambda _e: str(uuid4()),
        apply=True,
    )
    assert report.deleted_unlinked == 1
    assert report.linked == []
    assert report.ok_for_credential_drop
    await db.refresh(user)
    assert user.auth_user_id is None


@pytest.mark.asyncio
async def test_conflict_when_auth_id_already_owned(db, factory):
    auth_id = uuid4()
    owner = await factory.user(display_name='Owner')
    owner.auth_user_id = auth_id
    other = await factory.user(display_name='Other')
    other.email = 'other@students.livingstone.edu'
    other.auth_user_id = None
    await db.commit()

    report = await link_existing_auth_users(
        db,
        lookup_auth_id=lambda email: str(auth_id) if email == other.email else None,
        apply=True,
    )
    assert report.conflicts
    assert not report.ok_for_credential_drop
    await db.refresh(other)
    assert other.auth_user_id is None


def test_is_live_account():
    live = User(email='a@students.livingstone.edu')
    assert is_live_account(live)
    dead = User(email='b@students.livingstone.edu', status='deleted')
    assert not is_live_account(dead)
