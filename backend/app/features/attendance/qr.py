"""Signed rotating QR challenges for Honors attendance."""

from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from app.config import settings

QR_PROTOCOL_VERSION = 1
_CLOCK_SKEW_SECONDS = 2


@dataclass(frozen=True, slots=True)
class QRChallenge:
    version: int
    session_id: UUID
    challenge_id: UUID
    expires_at: datetime
    token: str

    def as_payload(self) -> dict[str, str | int]:
        return {
            'v': self.version,
            'session_id': str(self.session_id),
            'challenge_id': str(self.challenge_id),
            'expires_at': self.expires_at.isoformat(),
            'token': self.token,
        }


def signing_secret_configured() -> bool:
    return bool(settings.attendance_qr_signing_secret)


def _signing_bytes() -> bytes:
    secret = settings.attendance_qr_signing_secret
    if not secret:
        raise ValueError('ATTENDANCE_QR_SIGNING_SECRET is not configured')
    return secret.encode('utf-8')


def _signing_message(*, session_id: UUID, challenge_id: UUID, expires_at: datetime) -> bytes:
    # ISO-8601 must match what clients send back verbatim.
    payload = f'{session_id}:{challenge_id}:{expires_at.isoformat()}'
    return payload.encode('utf-8')


def sign_challenge(*, session_id: UUID, challenge_id: UUID, expires_at: datetime) -> str:
    digest = hmac.new(_signing_bytes(), _signing_message(
        session_id=session_id, challenge_id=challenge_id, expires_at=expires_at
    ), hashlib.sha256)
    return digest.hexdigest()


def verify_challenge_token(
    *,
    session_id: UUID,
    challenge_id: UUID,
    expires_at: datetime,
    token: str,
) -> bool:
    if not token or not signing_secret_configured():
        return False
    expected = sign_challenge(session_id=session_id, challenge_id=challenge_id, expires_at=expires_at)
    return hmac.compare_digest(expected, token)


def build_challenge(session_id: UUID, *, ttl_seconds: int | None = None) -> QRChallenge:
    ttl = ttl_seconds if ttl_seconds is not None else settings.attendance_qr_ttl_seconds
    challenge_id = uuid4()
    expires_at = datetime.now(UTC) + timedelta(seconds=ttl)
    token = sign_challenge(session_id=session_id, challenge_id=challenge_id, expires_at=expires_at)
    return QRChallenge(
        version=QR_PROTOCOL_VERSION,
        session_id=session_id,
        challenge_id=challenge_id,
        expires_at=expires_at,
        token=token,
    )


def parse_expires_at(value: str) -> datetime:
    """Parse client-submitted expiry; raises ValueError on bad input."""
    parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def challenge_not_expired(expires_at: datetime, *, now: datetime | None = None) -> bool:
    current = now or datetime.now(UTC)
    return expires_at + timedelta(seconds=_CLOCK_SKEW_SECONDS) >= current
