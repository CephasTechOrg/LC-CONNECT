"""POST /auth/forgot-password — public, DB-free, and never confirms/denies account existence."""

from __future__ import annotations

import importlib

from fastapi.testclient import TestClient

from app.main import app

# `app/features/auth/__init__.py` does `from .router import router`, which shadows the
# `app.features.auth.router` *submodule* attribute with the APIRouter instance itself — fetch the
# real submodule straight from sys.modules instead so we can monkeypatch its module-level names.
auth_router = importlib.import_module('app.features.auth.router')

client = TestClient(app)


def test_forgot_password_always_returns_same_message(monkeypatch):
    monkeypatch.setattr(auth_router, 'request_password_reset', lambda email, **kwargs: True)
    response = client.post('/api/v1/auth/forgot-password', json={'email': 'a@b.com', 'portal': 'admin'})
    assert response.status_code == 200
    assert 'reset link has been sent' in response.json()['message']


def test_forgot_password_same_message_even_when_reset_fails(monkeypatch):
    """Never leak whether the account exists or the send failed — same response either way."""
    monkeypatch.setattr(auth_router, 'request_password_reset', lambda email, **kwargs: False)
    response = client.post('/api/v1/auth/forgot-password', json={'email': 'nobody@b.com', 'portal': 'employer'})
    assert response.status_code == 200
    assert 'reset link has been sent' in response.json()['message']


def test_forgot_password_passes_correct_portal_redirect(monkeypatch):
    captured = {}

    def _fake(email, *, redirect_to=None):
        captured['email'] = email
        captured['redirect_to'] = redirect_to
        return True

    monkeypatch.setattr(auth_router, 'request_password_reset', _fake)
    monkeypatch.setattr(auth_router.settings, 'employer_portal_url', 'http://localhost:3001')
    monkeypatch.setattr(auth_router.settings, 'admin_portal_url', 'http://localhost:3000')

    client.post('/api/v1/auth/forgot-password', json={'email': 'a@b.com', 'portal': 'employer'})
    assert captured['redirect_to'] == 'http://localhost:3001/reset-password'

    client.post('/api/v1/auth/forgot-password', json={'email': 'a@b.com', 'portal': 'admin'})
    assert captured['redirect_to'] == 'http://localhost:3000/reset-password'


def test_forgot_password_invalid_portal_is_422():
    response = client.post('/api/v1/auth/forgot-password', json={'email': 'a@b.com', 'portal': 'mobile'})
    assert response.status_code == 422
