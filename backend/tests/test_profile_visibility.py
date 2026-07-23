"""Centralized profile-visibility policy: hidden / verified-only / block enforcement.

DB-free — the block lookup is exercised through a mocked session.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.shared.policies import assert_profile_visible


def _viewer(*, is_verified=True, uid=None):
    return SimpleNamespace(id=uid or uuid4(), is_verified=is_verified)


def _profile(*, owner=None, is_hidden=False, verified_only=False):
    return SimpleNamespace(
        user_id=owner or uuid4(),
        is_hidden=is_hidden,
        show_profile_to_verified_only=verified_only,
    )


def _db(*, blocked=False):
    result = MagicMock()
    result.scalar_one_or_none.return_value = object() if blocked else None
    db = MagicMock()
    db.execute = AsyncMock(return_value=result)
    return db


async def test_ordinary_visible_profile_ok():
    await assert_profile_visible(_db(), viewer=_viewer(), profile=_profile())


async def test_own_profile_always_visible_even_if_hidden_and_verified_only():
    me = uuid4()
    await assert_profile_visible(
        _db(),
        viewer=_viewer(uid=me, is_verified=False),
        profile=_profile(owner=me, is_hidden=True, verified_only=True),
    )


async def test_hidden_profile_is_404():
    with pytest.raises(HTTPException) as exc:
        await assert_profile_visible(_db(), viewer=_viewer(), profile=_profile(is_hidden=True))
    assert exc.value.status_code == 404


async def test_verified_only_hides_from_unverified_viewer():
    with pytest.raises(HTTPException) as exc:
        await assert_profile_visible(
            _db(), viewer=_viewer(is_verified=False), profile=_profile(verified_only=True)
        )
    assert exc.value.status_code == 404


async def test_verified_only_visible_to_verified_viewer():
    await assert_profile_visible(
        _db(), viewer=_viewer(is_verified=True), profile=_profile(verified_only=True)
    )


async def test_blocked_users_cannot_see_each_other():
    with pytest.raises(HTTPException) as exc:
        await assert_profile_visible(_db(blocked=True), viewer=_viewer(), profile=_profile())
    assert exc.value.status_code == 404


async def test_self_view_skips_the_block_query():
    me = uuid4()
    db = _db(blocked=True)  # even a (bogus) block must not matter for self-view
    await assert_profile_visible(db, viewer=_viewer(uid=me), profile=_profile(owner=me))
    db.execute.assert_not_awaited()
