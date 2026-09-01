"""QR signing and expiry helpers — no database."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.config import settings
from app.features.attendance import qr


@pytest.fixture(autouse=True)
def _signing_secret(monkeypatch):
    monkeypatch.setattr(settings, 'attendance_qr_signing_secret', 'unit-test-signing-secret')


def test_sign_and_verify_round_trip():
    session_id = uuid4()
    challenge_id = uuid4()
    expires_at = datetime.now(UTC) + timedelta(seconds=10)
    token = qr.sign_challenge(session_id=session_id, challenge_id=challenge_id, expires_at=expires_at)
    assert qr.verify_challenge_token(
        session_id=session_id,
        challenge_id=challenge_id,
        expires_at=expires_at,
        token=token,
    )


def test_verify_rejects_tampered_token():
    session_id = uuid4()
    challenge_id = uuid4()
    expires_at = datetime.now(UTC) + timedelta(seconds=10)
    token = qr.sign_challenge(session_id=session_id, challenge_id=challenge_id, expires_at=expires_at)
    assert not qr.verify_challenge_token(
        session_id=session_id,
        challenge_id=challenge_id,
        expires_at=expires_at,
        token=token + 'x',
    )


def test_verify_rejects_wrong_session():
    session_id = uuid4()
    challenge_id = uuid4()
    expires_at = datetime.now(UTC) + timedelta(seconds=10)
    token = qr.sign_challenge(session_id=session_id, challenge_id=challenge_id, expires_at=expires_at)
    assert not qr.verify_challenge_token(
        session_id=uuid4(),
        challenge_id=challenge_id,
        expires_at=expires_at,
        token=token,
    )


def test_challenge_not_expired_honors_small_skew():
    expires_at = datetime.now(UTC) - timedelta(seconds=1)
    assert qr.challenge_not_expired(expires_at)


def test_challenge_expired_beyond_skew():
    expires_at = datetime.now(UTC) - timedelta(seconds=5)
    assert not qr.challenge_not_expired(expires_at)


def test_build_challenge_payload_shape():
    session_id = uuid4()
    challenge = qr.build_challenge(session_id, ttl_seconds=10)
    payload = challenge.as_payload()
    assert payload['v'] == qr.QR_PROTOCOL_VERSION
    assert payload['session_id'] == str(session_id)
    assert payload['token']
