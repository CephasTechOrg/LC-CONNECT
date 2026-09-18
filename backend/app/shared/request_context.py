"""Request correlation IDs for incident debugging.

Every HTTP request gets a stable ``X-Request-ID`` (client-provided or generated). The id is:
- echoed on the response so mobile/clients can report it in bug reports,
- stored in a ``contextvars.ContextVar`` so log lines and audit helpers can attach it
  without threading an argument through every call site.

WebSocket upgrade requests also get an id (useful when the handshake fails before the
gateway's own protocol takes over).

The same middleware also times every HTTP request. Uvicorn's access log records method, path and
status but **no duration**, which left every latency question in the beta review unanswerable from
production logs — cold-start cost, p50/p95 per endpoint, and whether co-locating the API with the
database actually paid off. One line per request with `duration_ms` makes all of those a matter of
reading logs rather than guessing.
"""

from __future__ import annotations

import logging
import re
import time
from collections.abc import Awaitable, Callable
from contextvars import ContextVar
from uuid import uuid4

from app.config import get_settings

Scope = dict
Message = dict
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]

# Restrict client-supplied ids: printable, short, no whitespace / control chars.
_CLIENT_ID_RE = re.compile(r'^[A-Za-z0-9._-]{8,128}$')

request_id_var: ContextVar[str | None] = ContextVar('request_id', default=None)

_HEADER = b'x-request-id'

#: Timing lines go here so they can be filtered separately from application logs.
_access_logger = logging.getLogger('lc_connect.access')


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
    """Pure-ASGI middleware — works for HTTP and the WebSocket handshake.

    Also emits one timing line per HTTP request. WebSockets are deliberately excluded: a socket
    lives for minutes, so its "duration" measures how long the user kept the app open and would
    say nothing about latency.
    """

    def __init__(self, app) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope.get('type') not in {'http', 'websocket'}:
            await self.app(scope, receive, send)
            return

        incoming = _parse_incoming(list(scope.get('headers') or ()))
        request_id = incoming or str(uuid4())
        token = request_id_var.set(request_id)
        is_http = scope.get('type') == 'http'
        started = time.perf_counter()
        # Mutable so `send_with_id` can report the status back out to the logging below.
        status_seen: list[int] = []

        async def send_with_id(message: Message) -> None:
            if message.get('type') == 'http.response.start':
                status_seen.append(int(message.get('status', 0)))
                headers = list(message.get('headers') or [])
                # Replace any prior X-Request-ID so the response always matches our context.
                headers = [(n, v) for n, v in headers if n.lower() != _HEADER]
                headers.append((_HEADER, request_id.encode('ascii')))
                message = {**message, 'headers': headers}
            await send(message)

        try:
            await self.app(scope, receive, send_with_id if is_http else send)
        except Exception:
            # An unhandled error is the single most useful thing to have a duration for, so log it
            # before re-raising rather than losing the timing to the exception path.
            if is_http:
                _log_request(scope, 500, time.perf_counter() - started)
            raise
        else:
            if is_http:
                _log_request(scope, status_seen[0] if status_seen else 0,
                             time.perf_counter() - started)
        finally:
            request_id_var.reset(token)


def _log_request(scope: Scope, status: int, elapsed_seconds: float) -> None:
    """One line per request: method, path, status, duration.

    The **path only** — never the query string. Ids in a path (`/messages/threads/<uuid>`) are what
    make a slow request diagnosable; a query string can carry a token or a search term a user typed,
    and neither belongs in a log that gets pasted into a bug report.

    Slow requests log at WARNING so they can be found with a level filter instead of by reading
    everything, which is the difference between logs that get used and logs that do not.
    """
    duration_ms = elapsed_seconds * 1000
    message = '%s %s -> %d in %.1fms'
    args = (scope.get('method', '?'), scope.get('path', '?'), status, duration_ms)
    if duration_ms >= get_settings().slow_request_ms:
        _access_logger.warning(message + ' [slow]', *args)
    else:
        _access_logger.info(message, *args)


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
