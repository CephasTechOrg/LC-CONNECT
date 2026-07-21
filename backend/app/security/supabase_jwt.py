"""Verify Supabase Auth access tokens via JWKS (asymmetric) or project JWT secret (HS256)."""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass
from typing import Any
from uuid import UUID

import httpx
import jwt
from jwt import PyJWK

from app.config import settings

_JWKS_TTL_SECONDS = 3600
_ALLOWED_ALGS = frozenset({'RS256', 'ES256', 'HS256'})


@dataclass(frozen=True, slots=True)
class SupabaseClaims:
    sub: UUID
    email: str
    role: str
    aal: str
    email_verified: bool
    raw: dict[str, Any]


class _JwksCache:
    __slots__ = ('_keys', '_fetched_at', '_lock')

    def __init__(self) -> None:
        self._keys: dict[str, PyJWK] = {}
        self._fetched_at: float = 0.0
        self._lock = asyncio.Lock()

    async def get(self, kid: str | None, *, force: bool = False) -> PyJWK | None:
        if not kid:
            return None
        now = time.monotonic()
        if not force and kid in self._keys and now - self._fetched_at < _JWKS_TTL_SECONDS:
            return self._keys[kid]

        async with self._lock:
            now = time.monotonic()
            if not force and kid in self._keys and now - self._fetched_at < _JWKS_TTL_SECONDS:
                return self._keys[kid]
            await self._refresh()
            return self._keys.get(kid)

    async def _refresh(self) -> None:
        url = settings.supabase_jwks_url
        if not url:
            return
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url)
            response.raise_for_status()
            body = response.json()
        keys: dict[str, PyJWK] = {}
        for item in body.get('keys', []):
            jwk = PyJWK.from_dict(item)
            if jwk.key_id:
                keys[jwk.key_id] = jwk
        self._keys = keys
        self._fetched_at = time.monotonic()


_jwks_cache = _JwksCache()


def _issuer() -> str | None:
    if not settings.supabase_url:
        return None
    return f'{settings.supabase_url.rstrip("/")}/auth/v1'


def _email_verified(payload: dict[str, Any]) -> bool:
    if payload.get('email_confirmed_at') or payload.get('email_verified') is True:
        return True
    user_meta = payload.get('user_metadata') or {}
    if isinstance(user_meta, dict):
        if user_meta.get('email_verified') is False:
            return False
        if user_meta.get('email_verified') is True:
            return True
    # Access tokens are only issued for confirmed users when confirmations are enabled.
    return True


async def verify_supabase_access_token(token: str) -> SupabaseClaims:
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError as exc:
        raise ValueError('Invalid token header') from exc

    alg = header.get('alg')
    if alg not in _ALLOWED_ALGS:
        raise ValueError('Unsupported token algorithm')

    options: dict[str, Any] = {
        'require': ['exp', 'sub', 'role'],
        'verify_aud': bool(settings.supabase_jwt_audience),
        'verify_iss': bool(_issuer()),
    }
    decode_kwargs: dict[str, Any] = {
        'algorithms': [alg],
        'options': options,
        'leeway': 10,
    }
    issuer = _issuer()
    if issuer:
        decode_kwargs['issuer'] = issuer
    if settings.supabase_jwt_audience:
        decode_kwargs['audience'] = settings.supabase_jwt_audience

    if alg == 'HS256':
        if not settings.supabase_jwt_secret:
            raise ValueError('HS256 token requires SUPABASE_JWT_SECRET')
        key: Any = settings.supabase_jwt_secret
    else:
        kid = header.get('kid')
        jwk = await _jwks_cache.get(kid)
        if jwk is None:
            jwk = await _jwks_cache.get(kid, force=True)
        if jwk is None:
            raise ValueError('Signing key not found')
        key = jwk.key

    try:
        payload = jwt.decode(token, key, **decode_kwargs)
    except jwt.PyJWTError as exc:
        raise ValueError('Invalid or expired token') from exc

    if payload.get('role') != 'authenticated':
        raise ValueError('Unexpected token role')

    email = str(payload.get('email') or '').lower().strip()
    if not email:
        raise ValueError('Token missing email')

    try:
        sub = UUID(str(payload['sub']))
    except (ValueError, TypeError, KeyError) as exc:
        raise ValueError('Token missing subject') from exc

    return SupabaseClaims(
        sub=sub,
        email=email,
        role=str(payload.get('role')),
        aal=str(payload.get('aal') or 'aal1'),
        email_verified=_email_verified(payload),
        raw=payload,
    )
