"""Supabase Auth admin client wrapper — invite/delete/ping never raise, and invite passes through
`redirect_to` so admin and employer invites can land in their own separate portal.

`invite_auth_user` deliberately uses `generate_link` (never sends an email itself) and sends LC
Connect's own branded email via `app.email.send_invite_email` — never Supabase's own mailer/
template. See `app/shared/supabase_admin.py` for why."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from app.shared import supabase_admin


class _FakeAdminAPI:
    def __init__(self):
        self.generate_link_calls: list[dict] = []
        self.list_users_calls = 0
        self.delete_calls: list[str] = []
        self.fail = False

    def generate_link(self, params):
        self.generate_link_calls.append(params)
        if self.fail:
            raise RuntimeError('boom')
        return SimpleNamespace(
            user=SimpleNamespace(id='new-auth-id'),
            properties=SimpleNamespace(action_link='https://supabase.example/verify?token=abc', email_otp='12345678'),
        )

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


def _mock_send_invite_email(monkeypatch) -> list[dict]:
    """`invite_auth_user` calls the real Resend-backed `send_invite_email` — never let a test
    actually hit that; capture the call instead so we can assert on what would have been sent."""
    calls: list[dict] = []

    def _fake(to_email, *, page_url, code, context='admin'):
        calls.append({'to_email': to_email, 'page_url': page_url, 'code': code, 'context': context})

    monkeypatch.setattr(supabase_admin.email_service, 'send_invite_email', _fake)
    return calls


def test_invite_auth_user_passes_redirect_to(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    _mock_send_invite_email(monkeypatch)
    auth_id = supabase_admin.invite_auth_user('a@b.com', redirect_to='https://admin.example.com/accept-invite')
    assert auth_id == 'new-auth-id'
    assert fake.admin.generate_link_calls == [
        {'type': 'invite', 'email': 'a@b.com', 'options': {'redirect_to': 'https://admin.example.com/accept-invite'}}
    ]


def test_invite_auth_user_no_redirect_to_passes_empty_options(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    _mock_send_invite_email(monkeypatch)
    supabase_admin.invite_auth_user('a@b.com')
    assert fake.admin.generate_link_calls == [{'type': 'invite', 'email': 'a@b.com', 'options': {}}]


def test_invite_auth_user_sends_own_branded_email_never_supabases(monkeypatch):
    """The whole point of `generate_link` over `invite_user_by_email`: Supabase never sends
    anything itself, LC Connect composes and sends the one and only invite email."""
    _install_fake_client(monkeypatch)
    sent = _mock_send_invite_email(monkeypatch)
    supabase_admin.invite_auth_user('a@b.com', context='employer')
    assert sent == [
        {
            'to_email': 'a@b.com',
            'page_url': None,
            'code': '12345678',
            'context': 'employer',
        }
    ]


def test_invite_auth_user_returns_none_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_admin, '_client', None)
    assert supabase_admin.invite_auth_user('a@b.com') is None


def test_invite_auth_user_returns_none_on_exception(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    fake.admin.fail = True
    assert supabase_admin.invite_auth_user('a@b.com') is None


def _mock_send_password_reset_email(monkeypatch) -> list[dict]:
    calls: list[dict] = []

    def _fake(to_email, *, page_url, code):
        calls.append({'to_email': to_email, 'page_url': page_url, 'code': code})

    monkeypatch.setattr(supabase_admin.email_service, 'send_password_reset_email', _fake)
    return calls


def test_request_password_reset_uses_recovery_type_and_sends_own_email(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    sent = _mock_send_password_reset_email(monkeypatch)

    result = supabase_admin.request_password_reset('a@b.com', redirect_to='https://x.com/reset-password')
    assert result is True
    assert fake.admin.generate_link_calls == [
        {'type': 'recovery', 'email': 'a@b.com', 'options': {'redirect_to': 'https://x.com/reset-password'}}
    ]
    assert sent == [
        {'to_email': 'a@b.com', 'page_url': 'https://x.com/reset-password', 'code': '12345678'}
    ]


def test_invite_raises_already_registered_for_existing_signup(monkeypatch):
    """Supabase refuses to invite an email that already completed sign-up. That must surface as a
    distinct, catchable signal — not a generic None — because the remedy is a password reset, not
    another invite. (Verified against the live Supabase API before writing this.)"""
    fake = _install_fake_client(monkeypatch)
    _mock_send_invite_email(monkeypatch)

    def _already_registered(params):
        raise RuntimeError('A user with this email address has already been registered')

    fake.admin.generate_link = _already_registered
    with pytest.raises(supabase_admin.AuthUserAlreadyRegistered):
        supabase_admin.invite_auth_user('taken@b.com')


def test_invite_still_returns_none_for_other_failures(monkeypatch):
    """An outage must stay distinguishable from 'already registered'."""
    fake = _install_fake_client(monkeypatch)
    fake.admin.fail = True
    assert supabase_admin.invite_auth_user('a@b.com') is None


def test_get_auth_user_id_by_email_matches_case_insensitively(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    fake.admin.list_users = lambda page=None, per_page=None: (
        [SimpleNamespace(id='found-id', email='Person@B.com')] if page == 1 else []
    )
    assert supabase_admin.get_auth_user_id_by_email('person@b.com') == 'found-id'


def test_get_auth_user_id_by_email_none_when_absent(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    fake.admin.list_users = lambda page=None, per_page=None: []
    assert supabase_admin.get_auth_user_id_by_email('nobody@b.com') is None


def test_request_password_reset_false_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_admin, '_client', None)
    assert supabase_admin.request_password_reset('a@b.com') is False


def test_request_password_reset_false_on_exception(monkeypatch):
    fake = _install_fake_client(monkeypatch)
    fake.admin.fail = True
    assert supabase_admin.request_password_reset('a@b.com') is False


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
