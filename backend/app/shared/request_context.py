"""Request correlation IDs for incident debugging.

Every HTTP request gets a stable ``X-Request-ID`` (client-provided or generated). The id is:
- echoed on the response so mobile/clients can report it in bug reports,
- stored in a ``contextvars.ContextVar`` so log lines and audit helpers can attach it
  without threading an argument through every call site.

WebSocket upgrade requests also get an id (useful when the handshake fails before the
gateway's own protocol takes over).
"""

from __future__ import annotations

import logging
import re
from collections.abc import Awaitable, Callable
from contextvars import ContextVar
from uuid import uuid4

Scope = dict
Message = dict
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]

# Restrict client-supplied ids: printable, short, no whitespace / control chars.
_CLIENT_ID_RE = re.compile(r'^[A-Za-z0-9._-]{8,128}$')

request_id_var: ContextVar[str | None] = ContextVar('request_id', default=None)

_HEADER = b'x-request-id'


def get_request_id() -> str | None:
    return request_id_var.get()


def _parse_incoming(headers: list[tuple[bytes, bytes]]) -> str | None:
    for name, value in headers:
        if name.lower() == _HEADER:
            try:
                candidate = value.decode('ascii').strip()
            except UnicodeDecodeError:
                return None
            if _CLIENT_ID_RE.match(candidate):
                return candidate
            return None
    return None


class RequestIdMiddleware:
    """Pure-ASGI middleware — works for HTTP and the WebSocket handshake."""

    def __init__(self, app) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope.get('type') not in {'http', 'websocket'}:
            await self.app(scope, receive, send)
            return

        incoming = _parse_incoming(list(scope.get('headers') or ()))
        request_id = incoming or str(uuid4())
        token = request_id_var.set(request_id)

        async def send_with_id(message: Message) -> None:
            if message.get('type') == 'http.response.start':
                headers = list(message.get('headers') or [])
                # Replace any prior X-Request-ID so the response always matches our context.
                headers = [(n, v) for n, v in headers if n.lower() != _HEADER]
                headers.append((_HEADER, request_id.encode('ascii')))
                message = {**message, 'headers': headers}
            await send(message)

        try:
            await self.app(scope, receive, send_with_id if scope.get('type') == 'http' else send)
        finally:
            request_id_var.reset(token)


class RequestIdFilter(logging.Filter):
    """Inject ``request_id`` into every log record (``-`` when outside a request)."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = get_request_id() or '-'  # type: ignore[attr-defined]
        return True


class RequestIdFormatter(logging.Formatter):
    """Formatter that always has ``request_id`` — safe for background tasks and child loggers."""

    def format(self, record: logging.LogRecord) -> str:
        if not hasattr(record, 'request_id'):
            record.request_id = get_request_id() or '-'  # type: ignore[attr-defined]
        return super().format(record)


def configure_request_id_logging(logger: logging.Logger) -> None:
    """Attach filter + ``[req=…]`` formatter on ``lc_connect`` log handlers."""
    if any(isinstance(f, RequestIdFilter) for f in logger.filters):
        return
    logger.addFilter(RequestIdFilter())
    formatter = RequestIdFormatter('%(levelname)s:     [%(name)s] [req=%(request_id)s] %(message)s')
    for handler in logger.handlers:
        handler.setFormatter(formatter)
    # Child loggers (e.g. ``lc_connect.realtime``) propagate here — ensure they inherit the filter.
    logger.propagate = False
