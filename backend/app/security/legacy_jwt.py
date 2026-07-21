"""Custom HS256 app tokens — retained only for the Phase 1 rollback window."""

from datetime import UTC, datetime, timedelta
from uuid import UUID

from jose import JWTError, jwt

from app.config import settings


def create_access_token(user_id: UUID) -> str:
    now = datetime.now(UTC)
    payload = {
        'sub': str(user_id),
        'role': 'authenticated',
        'type': 'access',
        'iat': now,
        'exp': now + timedelta(minutes=settings.access_token_expire_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> UUID | None:
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        if payload.get('type') != 'access':
            return None
        return UUID(str(payload.get('sub')))
    except (JWTError, ValueError, TypeError):
        return None
