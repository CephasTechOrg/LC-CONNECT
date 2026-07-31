"""Supabase Auth admin client wrapper — invite/delete/ping never raise, and invite passes through
`redirect_to` so admin and employer invites can land in their own separate portal."""

from __future__ import annotations

from types import SimpleNamespace

from app.shared import supabase_admin


class _FakeAdminAPI:
    def __init__(self):
        self.invite_calls: list[tuple[str, dict | None]] = []
        self.list_users_calls = 0
        self.delete_calls: list[str] = []
        self.fail = False

    def invite_user_by_email(self, email, options=None):
        self.invite_calls.append((email, options))
        if self.fail:
            raise RuntimeError('boom')
        return SimpleNamespace(user=SimpleNamespace(id='new-auth-id'))

    def list_users(self, page=None, per_page=None):
        self.list_users_calls += 1
        if self.fail:
            raise RuntimeError('boom')
        return []

    def delete_user(self, auth_user_id):
        self.delete_calls.append(auth_user_id)
        if self.fail:
            raise RuntimeError('boom')


class _FakeClient:
    def __init__(self):
        self.admin = _FakeAdminAPI()

    @property
    def auth(self):
        return self


def _install_fake_client(monkeypatch) -> _FakeClient:
    fake = _FakeClient()
    monkeypatch.setattr(supabase_admin, '_client', fake)
    return fake


def test_invite_auth_user_passes_redirect_to(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    auth_id = supabase_admin.invite_auth_user('a@b.com', redirect_to='https://admin.example.com/accept-invite')
    assert auth_id == 'new-auth-id'
    assert fake.admin.invite_calls == [('a@b.com', {'redirect_to': 'https://admin.example.com/accept-invite'})]


def test_invite_auth_user_no_redirect_to_passes_none_options(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    supabase_admin.invite_auth_user('a@b.com')
    assert fake.admin.invite_calls == [('a@b.com', None)]


def test_invite_auth_user_returns_none_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_admin, '_client', None)
    assert supabase_admin.invite_auth_user('a@b.com') is None


def test_invite_auth_user_returns_none_on_exception(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    fake.admin.fail = True
    assert supabase_admin.invite_auth_user('a@b.com') is None


def test_ping_true_when_reachable(monkeypatch):
    _install_fake_client(monkeypatch)
    assert supabase_admin.ping() is True


def test_ping_false_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_admin, '_client', None)
    assert supabase_admin.ping() is False


def test_ping_false_on_exception(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    fake.admin.fail = True
    assert supabase_admin.ping() is False


def test_delete_auth_user_true_on_success(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    assert supabase_admin.delete_auth_user('some-id') is True
    assert fake.admin.delete_calls == ['some-id']


def test_delete_auth_user_false_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_admin, '_client', None)
    assert supabase_admin.delete_auth_user('some-id') is False


def test_delete_auth_user_false_on_exception(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    fake.admin.fail = True
    assert supabase_admin.delete_auth_user('some-id') is False
