"""Abuse limits on the endpoints that must stay open to anonymous callers.

Found during a hardening pass: `/auth/forgot-password` and `/employers/register` had no limit of
any kind. `UserRateLimit` keys on `User.id`, which does not exist without a session — so those
two were effectively unlimited, letting anyone bomb a victim's inbox (burning the transactional
email quota) or flood the Honors approval queue with junk organisations.
"""

from __future__ import annotations

import pytest
from fastapi import HTTPException, Request

from app.shared.rate_limit import KeyedRateLimit, PublicRateLimit, client_ip


def _request(headers: dict[str, str] | None = None, peer: str | None = '203.0.113.9') -> Request:
    raw = [(k.lower().encode(), v.encode()) for k, v in (headers or {}).items()]
    scope = {'type': 'http', 'headers': raw, 'client': (peer, 1234) if peer else None}
    return Request(scope)


# ── client_ip ────────────────────────────────────────────────────────────────────


def test_client_ip_prefers_first_forwarded_hop():
    """Behind a proxy the socket peer is the proxy — the first X-Forwarded-For hop is the caller."""
    req = _request({'x-forwarded-for': '198.51.100.7, 10.0.0.1, 10.0.0.2'})
    assert client_ip(req) == '198.51.100.7'


def test_client_ip_falls_back_to_socket_peer():
    assert client_ip(_request()) == '203.0.113.9'


def test_client_ip_handles_missing_client():
    assert client_ip(_request(peer=None)) == 'unknown'


def test_client_ip_ignores_blank_forwarded_header():
    assert client_ip(_request({'x-forwarded-for': '   '})) == '203.0.113.9'


# ── PublicRateLimit ──────────────────────────────────────────────────────────────


async def test_public_limit_allows_up_to_limit_then_429():
    limit = PublicRateLimit('t', 3, 3600, 'slow down')
    req = _request({'x-forwarded-for': '198.51.100.1'})
    for _ in range(3):
        await limit(req)  # must not raise
    with pytest.raises(HTTPException) as exc:
        await limit(req)
    assert exc.value.status_code == 429
    assert exc.value.detail == 'slow down'


async def test_public_limit_is_per_ip_not_global():
    """One abuser must never lock everyone else out."""
    limit = PublicRateLimit('t', 1, 3600, 'slow down')
    await limit(_request({'x-forwarded-for': '198.51.100.1'}))
    with pytest.raises(HTTPException):
        await limit(_request({'x-forwarded-for': '198.51.100.1'}))
    # A different caller still gets through.
    await limit(_request({'x-forwarded-for': '198.51.100.2'}))


# ── KeyedRateLimit (per-email) ───────────────────────────────────────────────────


def test_keyed_limit_caps_per_key_then_429():
    limit = KeyedRateLimit('t', 2, 3600, 'too many')
    limit.check('victim@livingstone.edu')
    limit.check('victim@livingstone.edu')
    with pytest.raises(HTTPException) as exc:
        limit.check('victim@livingstone.edu')
    assert exc.value.status_code == 429


def test_keyed_limit_is_case_and_whitespace_insensitive():
    """Otherwise 'Victim@x.com' and 'victim@x.com ' would each get their own fresh budget,
    defeating the per-inbox cap entirely."""
    limit = KeyedRateLimit('t', 1, 3600, 'too many')
    limit.check('victim@livingstone.edu')
    with pytest.raises(HTTPException):
        limit.check('  VICTIM@Livingstone.EDU  ')


def test_keyed_limit_separate_keys_are_independent():
    limit = KeyedRateLimit('t', 1, 3600, 'too many')
    limit.check('a@livingstone.edu')
    limit.check('b@livingstone.edu')  # must not raise
