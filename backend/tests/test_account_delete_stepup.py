"""Account deletion step-up auth — password required; bearer alone is not enough."""

from __future__ import annotations

from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user
from app.features.account import service as account_service
from app.main import app
from app.shared import supabase_admin


async def _dummy_db():
    yield None


@pytest.fixture(autouse=True)
def _clear_overrides():
    yield
    app.dependency_overrides.clear()


def _user(**overrides):
    base = {
        'id': uuid4(),
        'email': 'student@students.livingstone.edu',
        'auth_user_id': uuid4(),
        'is_active': True,
        'status': 'active',
        'is_verified': True,
        'role': 'student',
    }
    base.update(overrides)
    return SimpleNamespace(**base)


def _client_for(user) -> TestClient:
    app.dependency_overrides[get_current_user] = lambda: user
    app.dependency_overrides[get_db] = _dummy_db
    return TestClient(app)


def test_delete_requires_password_field():
    client = _client_for(_user())
    resp = client.request(
        'DELETE',
        '/api/v1/account',
        json={'confirm_email': 'student@students.livingstone.edu'},
    )
    assert resp.status_code == 422  # password missing


def test_delete_rejects_wrong_email_before_password_check(monkeypatch):
    called = {'verify': False}

    def _boom(*_a, **_k):
        called['verify'] = True
        return True

    monkeypatch.setattr(supabase_admin, 'verify_password_for_email', _boom)
    client = _client_for(_user())
    resp = client.request(
        'DELETE',
        '/api/v1/account',
        json={
            'confirm_email': 'other@students.livingstone.edu',
            'password': 'secret',
        },
    )
    assert resp.status_code == 400
    assert called['verify'] is False


def test_delete_rejects_incorrect_password(monkeypatch):
    monkeypatch.setattr(supabase_admin, 'verify_password_for_email', lambda *a, **k: False)

    async def _should_not_run(*_a, **_k):
        raise AssertionError('delete_account must not run without step-up')

    monkeypatch.setattr(account_service, 'delete_account', _should_not_run)

    client = _client_for(_user())
    resp = client.request(
        'DELETE',
        '/api/v1/account',
        json={
            'confirm_email': 'student@students.livingstone.edu',
            'password': 'wrong',
        },
    )
    assert resp.status_code == 403
    assert resp.json()['detail'] == 'Incorrect password'


def test_delete_succeeds_after_password_step_up(monkeypatch):
    calls: list[object] = []

    monkeypatch.setattr(supabase_admin, 'verify_password_for_email', lambda *a, **k: True)

    async def _fake_delete(db, user):
        calls.append(user)

    monkeypatch.setattr(account_service, 'delete_account', _fake_delete)

    user = _user()
    client = _client_for(user)
    resp = client.request(
        'DELETE',
        '/api/v1/account',
        json={
            'confirm_email': 'student@students.livingstone.edu',
            'password': 'correct-horse',
        },
    )
    assert resp.status_code == 200
    assert resp.json()['status'] == 'deleted'
    assert calls == [user]


def test_verify_password_false_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_admin.settings, 'supabase_url', None)
    monkeypatch.setattr(supabase_admin.settings, 'supabase_service_role_key', None)
    assert supabase_admin.verify_password_for_email('a@b.c', 'pw') is False
