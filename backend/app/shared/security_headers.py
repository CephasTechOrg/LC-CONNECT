"""Baseline HTTP security headers for API responses.

Applied to every HTTP response. HSTS is production-only so local HTTP
dev/test does not get sticky HTTPS requirements from a browser.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable

Scope = dict
Message = dict
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]

# API-only CSP: no script/style/img loads expected from this origin.
_BASE_HEADERS: list[tuple[bytes, bytes]] = [
    (b'x-content-type-options', b'nosniff'),
    (b'x-frame-options', b'DENY'),
    (b'referrer-policy', b'strict-origin-when-cross-origin'),
    (b'permissions-policy', b'geolocation=(), microphone=(), camera=()'),
    (
        b'content-security-policy',
        b"default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    ),
]

_HSTS = (b'strict-transport-security', b'max-age=31536000; includeSubDomains')

_PROTECTED = {name for name, _ in _BASE_HEADERS} | {_HSTS[0]}


class SecurityHeadersMiddleware:
    """Pure-ASGI middleware — sets security headers on ``http.response.start``."""

    def __init__(self, app, *, enable_hsts: bool = False) -> None:
        self.app = app
        self.enable_hsts = enable_hsts

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope.get('type') != 'http':
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message: Message) -> None:
            if message.get('type') == 'http.response.start':
                headers = [
                    (n, v)
                    for n, v in (message.get('headers') or [])
                    if n.lower() not in _PROTECTED
                ]
                headers.extend(_BASE_HEADERS)
                if self.enable_hsts:
                    headers.append(_HSTS)
                message = {**message, 'headers': headers}
            await send(message)

        await self.app(scope, receive, send_with_headers)
