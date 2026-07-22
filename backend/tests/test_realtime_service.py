"""Direct tests for the real realtime service functions.

The gateway tests monkeypatch these, so this file exercises the ACTUAL signatures
and logic (a regression guard for the user_id-vs-User bug found in on-device testing).
"""

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.features.realtime import service


class _FakeMatch:
    def __init__(self, user_a_id, user_b_id) -> None:
        self.user_a_id = user_a_id
        self.user_b_id = user_b_id


class _FakeDb:
    """Minimal async session stub: only .get(Match, id) is used here."""

    def __init__(self, match) -> None:
        self._match = match

    async def get(self, _model, _pk):
        return self._match


async def test_authorize_conversation_allows_member(monkeypatch):
    a, b = uuid4(), uuid4()
    monkeypatch.setattr(service, 'users_are_blocked', AsyncMock(return_value=False))
    match = await service.authorize_conversation(_FakeDb(_FakeMatch(a, b)), a, uuid4())
    assert match.user_a_id == a  # member is authorized, returns the match


async def test_authorize_conversation_rejects_non_member(monkeypatch):
    a, b = uuid4(), uuid4()
    monkeypatch.setattr(service, 'users_are_blocked', AsyncMock(return_value=False))
    with pytest.raises(service.WsForbidden):
        await service.authorize_conversation(_FakeDb(_FakeMatch(a, b)), uuid4(), uuid4())


async def test_authorize_conversation_rejects_blocked(monkeypatch):
    a, b = uuid4(), uuid4()
    monkeypatch.setattr(service, 'users_are_blocked', AsyncMock(return_value=True))
    with pytest.raises(service.WsForbidden):
        await service.authorize_conversation(_FakeDb(_FakeMatch(a, b)), a, uuid4())


async def test_authorize_conversation_rejects_missing_match():
    with pytest.raises(service.WsForbidden):
        await service.authorize_conversation(_FakeDb(None), uuid4(), uuid4())
