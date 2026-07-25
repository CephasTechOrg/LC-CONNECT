"""Edge guard: reject oversized request bodies before they're read.

The per-endpoint upload checks (`len(await file.read()) > cap`) only run *after* the multipart
body has been received and spooled — so they cap the stored file but don't stop a huge body from
being buffered first. This pure-ASGI middleware inspects `Content-Length` and rejects early with a
413, before the app (and the multipart parser) ever touch the body.

Chunked requests (no Content-Length) and a spoofed-small Content-Length still fall through to the
per-endpoint size check, which stays as the backstop.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable

Scope = dict
Message = dict
Receive = Callable[[], Awaitable[Message]]
Send = Callable[[Message], Awaitable[None]]


class MaxBodySizeMiddleware:
    def __init__(self, app, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope.get('type') == 'http':
            for name, value in scope.get('headers', ()):
                if name == b'content-length':
                    try:
                        declared = int(value)
                    except ValueError:
                        break
                    if declared > self.max_bytes:
                        await send({
                            'type': 'http.response.start',
                            'status': 413,
                            'headers': [(b'content-type', b'application/json')],
                        })
                        await send({
                            'type': 'http.response.body',
                            'body': b'{"detail":"Request body too large"}',
                        })
                        return
                    break
        await self.app(scope, receive, send)
