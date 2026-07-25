"""Edge body-size guard: reject an oversized Content-Length before the app sees it."""

from __future__ import annotations

from app.shared.request_limits import MaxBodySizeMiddleware


def _scope(content_length: bytes | None):
    headers = [(b'host', b'test')]
    if content_length is not None:
        headers.append((b'content-length', content_length))
    return {'type': 'http', 'headers': headers}


async def _run(mw, scope):
    reached = {'app': False}

    async def app(_scope, _receive, _send):
        reached['app'] = True

    sent = []

    async def send(msg):
        sent.append(msg)

    async def receive():
        return {'type': 'http.request', 'body': b''}

    # bind a real downstream app for this run
    mw.app = app
    await mw(scope, receive, send)
    return reached['app'], sent


async def test_rejects_body_over_the_cap():
    mw = MaxBodySizeMiddleware(app=None, max_bytes=1000)
    reached_app, sent = await _run(mw, _scope(b'5000'))
    assert reached_app is False  # the app is never called
    assert sent[0]['status'] == 413


async def test_allows_body_within_the_cap():
    mw = MaxBodySizeMiddleware(app=None, max_bytes=1000)
    reached_app, sent = await _run(mw, _scope(b'500'))
    assert reached_app is True
    assert sent == []  # passed straight through to the app


async def test_allows_request_without_content_length():
    mw = MaxBodySizeMiddleware(app=None, max_bytes=1000)
    reached_app, _ = await _run(mw, _scope(None))  # e.g. chunked — falls through to per-endpoint check
    assert reached_app is True
