"""Supabase 'Send Email' Auth Hook — signature verification (via the real `standardwebhooks`
library, not a mock of it) and correct email-template routing per Supabase auth action type."""

from __future__ import annotations

import base64
import json
import time
from datetime import UTC, datetime
from uuid import uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from standardwebhooks.webhooks import Webhook

from app.features.auth import email_hook
from app.main import app

TEST_SECRET = 'whsec_' + base64.b64encode(b'test-signing-secret-32-bytes!!!!').decode()

client = TestClient(app)


def _signed_headers(secret: str, body: bytes) -> dict[str, str]:
    msg_id = f'msg_{uuid4().hex}'
    now = time.time()
    timestamp = datetime.fromtimestamp(now, tz=UTC)
    signature = Webhook(secret).sign(msg_id=msg_id, timestamp=timestamp, data=body.decode())
    return {'webhook-id': msg_id, 'webhook-timestamp': str(int(now)), 'webhook-signature': signature}


def _payload(
    action_type: str,
    email: str = 'a@b.com',
    *,
    contact_email: str | None = None,
) -> dict:
    user: dict = {'id': str(uuid4()), 'email': email}
    if contact_email is not None:
        user['user_metadata'] = {'contact_email': contact_email}
    return {
        'user': user,
        'email_data': {
            'token': '12345678',
            'token_hash': 'hashedtoken',
            'redirect_to': 'https://example.com/reset-password',
            'email_action_type': action_type,
            'site_url': 'https://example.com',
        },
    }


# ── verify_and_parse (real signature verification) ──────────────────────────────


class _FakeRequest:
    def __init__(self, body: bytes, headers: dict[str, str]):
        self._body = body
        self.headers = headers

    async def body(self) -> bytes:
        return self._body


async def test_verify_and_parse_accepts_valid_signature(monkeypatch):
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', TEST_SECRET)
    body = json.dumps(_payload('signup')).encode()
    headers = _signed_headers(TEST_SECRET, body)

    result = await email_hook.verify_and_parse(_FakeRequest(body, headers))
    assert result['email_data']['email_action_type'] == 'signup'


async def test_verify_and_parse_rejects_bad_signature(monkeypatch):
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', TEST_SECRET)
    body = json.dumps(_payload('signup')).encode()
    headers = _signed_headers('whsec_' + base64.b64encode(b'a-totally-different-secret-here!').decode(), body)

    with pytest.raises(HTTPException) as exc:
        await email_hook.verify_and_parse(_FakeRequest(body, headers))
    assert exc.value.status_code == 401


async def test_verify_and_parse_503_when_unconfigured(monkeypatch):
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', None)
    with pytest.raises(HTTPException) as exc:
        await email_hook.verify_and_parse(_FakeRequest(b'{}', {}))
    assert exc.value.status_code == 503


# ── send_for_payload routing ────────────────────────────────────────────────────


def _capture(monkeypatch, fn_name: str) -> list[dict]:
    calls: list[dict] = []

    def _fake(to_email, *, code, page_url=None, **kwargs):
        calls.append({'to_email': to_email, 'page_url': page_url, 'code': code, **kwargs})

    monkeypatch.setattr(email_hook.email_service, fn_name, _fake)
    return calls


def test_send_for_payload_recovery_uses_password_reset_email(monkeypatch):
    calls = _capture(monkeypatch, 'send_password_reset_email')
    email_hook.send_for_payload(_payload('recovery', email='student@students.livingstone.edu'))
    assert calls[0]['to_email'] == 'student@students.livingstone.edu'
    assert calls[0]['code'] == '12345678'


def test_send_for_payload_invite_uses_invite_email(monkeypatch):
    calls = _capture(monkeypatch, 'send_invite_email')
    email_hook.send_for_payload(_payload('invite'))
    assert calls[0]['context'] == 'admin'


def test_send_for_payload_signup_routes_to_contact_email(monkeypatch):
    calls = _capture(monkeypatch, 'send_signup_confirmation_email')
    email_hook.send_for_payload(
        _payload(
            'signup',
            email='student@students.livingstone.edu',
            contact_email='student.personal@gmail.com',
        )
    )
    assert calls[0]['to_email'] == 'student.personal@gmail.com'
    assert calls[0]['campus_email'] == 'student@students.livingstone.edu'


def test_send_for_payload_recovery_routes_to_contact_email(monkeypatch):
    calls = _capture(monkeypatch, 'send_password_reset_email')
    email_hook.send_for_payload(
        _payload(
            'recovery',
            email='student@students.livingstone.edu',
            contact_email='student.personal@gmail.com',
        )
    )
    assert calls[0]['to_email'] == 'student.personal@gmail.com'


def test_send_for_payload_falls_back_when_contact_is_campus_domain(monkeypatch):
    calls = _capture(monkeypatch, 'send_signup_confirmation_email')
    email_hook.send_for_payload(
        _payload(
            'signup',
            email='student@students.livingstone.edu',
            contact_email='other@students.livingstone.edu',
        )
    )
    assert calls[0]['to_email'] == 'student@students.livingstone.edu'


def test_send_for_payload_signup_uses_confirmation_email(monkeypatch):
    calls = _capture(monkeypatch, 'send_signup_confirmation_email')
    email_hook.send_for_payload(_payload('signup'))
    assert calls[0]['code'] == '12345678'


def test_send_for_payload_unknown_type_falls_back_to_confirmation_email(monkeypatch):
    calls = _capture(monkeypatch, 'send_signup_confirmation_email')
    email_hook.send_for_payload(_payload('magiclink'))
    assert len(calls) == 1


def test_send_for_payload_missing_email_is_400():
    payload = _payload('signup')
    del payload['user']['email']
    with pytest.raises(HTTPException) as exc:
        email_hook.send_for_payload(payload)
    assert exc.value.status_code == 400


# ── full round-trip via the router ──────────────────────────────────────────────


def test_webhook_endpoint_end_to_end(monkeypatch):
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', TEST_SECRET)
    calls = _capture(monkeypatch, 'send_signup_confirmation_email')

    body = json.dumps(_payload('signup', email='new@students.livingstone.edu')).encode()
    headers = _signed_headers(TEST_SECRET, body)

    response = client.post('/api/v1/auth/webhooks/send-email', content=body, headers=headers)
    assert response.status_code == 200
    assert calls[0]['to_email'] == 'new@students.livingstone.edu'


def test_webhook_endpoint_rejects_forged_signature(monkeypatch):
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', TEST_SECRET)
    body = json.dumps(_payload('signup')).encode()
    bad_headers = {
        'webhook-id': 'msg_forged',
        'webhook-timestamp': str(int(time.time())),
        'webhook-signature': 'v1,not-a-real-signature==',
    }
    response = client.post('/api/v1/auth/webhooks/send-email', content=body, headers=bad_headers)
    assert response.status_code == 401


def test_webhook_endpoint_send_failure_uses_supabase_error_shape(monkeypatch):
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', TEST_SECRET)

    def _boom(to_email, **kwargs):
        raise RuntimeError('resend is down')

    monkeypatch.setattr(email_hook.email_service, 'send_signup_confirmation_email', _boom)

    body = json.dumps(_payload('signup')).encode()
    headers = _signed_headers(TEST_SECRET, body)
    response = client.post('/api/v1/auth/webhooks/send-email', content=body, headers=headers)
    assert response.status_code == 500
    assert response.json()['error']['http_code'] == 500


# ── Supabase's `v1,whsec_` secret format ────────────────────────────────────────


def _sign(secret_b64: str, payload: str) -> dict[str, str]:
    """Sign a payload the way Supabase does — with the RAW key, not the prefixed string."""
    from datetime import UTC, datetime

    from standardwebhooks.webhooks import Webhook

    ts = datetime.now(UTC)
    return {
        'webhook-id': 'msg_test',
        'webhook-timestamp': str(int(ts.timestamp())),
        'webhook-signature': Webhook(secret_b64).sign('msg_test', ts, payload),
    }


def test_verify_accepts_supabase_v1_whsec_secret_format(monkeypatch):
    """Supabase presents the secret as `v1,whsec_<base64>`; `standardwebhooks` only strips
    `whsec_`. Leaving `v1,` on silently base64-decodes to a *different key*, so every real
    Supabase call 401s — and because the hook is fail-closed, that blocks the signup or password
    reset behind it. Regression guard for a live outage this caused."""
    import base64
    import secrets as _secrets

    from fastapi.testclient import TestClient

    from app.main import app

    key_b64 = base64.b64encode(_secrets.token_bytes(32)).decode()
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', f'v1,whsec_{key_b64}')

    sent: list[tuple] = []
    monkeypatch.setattr(
        email_hook.email_service, 'send_password_reset_email',
        lambda to, **kw: sent.append((to, kw)),
    )

    payload = (
        '{"user":{"email":"a@livingstone.edu"},'
        '"email_data":{"email_action_type":"recovery","token":"123456"}}'
    )
    response = TestClient(app).post(
        '/api/v1/auth/webhooks/send-email',
        content=payload,
        headers={'content-type': 'application/json', **_sign(key_b64, payload)},
    )

    assert response.status_code == 200, response.text
    assert sent and sent[0][0] == 'a@livingstone.edu'


def test_verify_still_accepts_a_bare_whsec_secret(monkeypatch):
    """Don't regress the plain `whsec_<base64>` form the library already handled."""
    import base64
    import secrets as _secrets

    key_b64 = base64.b64encode(_secrets.token_bytes(32)).decode()
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', f'whsec_{key_b64}')
    assert email_hook._signing_secret() == f'whsec_{key_b64}'


def test_signing_secret_tolerates_whitespace(monkeypatch):
    """A trailing newline from a copy-paste into Render must not change the key."""
    monkeypatch.setattr(email_hook.settings, 'supabase_send_email_hook_secret', '  v1,whsec_AAAA\n')
    assert email_hook._signing_secret() == 'whsec_AAAA'
