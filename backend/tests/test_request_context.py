"""Request correlation id + timing middleware — DB-free."""

from __future__ import annotations

import logging
import re

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import get_settings
from app.main import app
from app.shared.request_context import RequestIdMiddleware, get_request_id, request_id_var


def test_response_includes_generated_request_id():
    client = TestClient(app)
    resp = client.get('/health')
    assert resp.status_code == 200
    rid = resp.headers.get('x-request-id')
    assert rid is not None
    assert len(rid) >= 8


def test_client_supplied_request_id_is_echoed():
    client = TestClient(app)
    resp = client.get('/health', headers={'X-Request-ID': 'client-trace-abc123'})
    assert resp.headers.get('x-request-id') == 'client-trace-abc123'


def test_invalid_client_request_id_is_replaced():
    client = TestClient(app)
    resp = client.get('/health', headers={'X-Request-ID': 'bad id with spaces'})
    rid = resp.headers.get('x-request-id')
    assert rid is not None
    assert rid != 'bad id with spaces'
    assert ' ' not in rid


def test_contextvar_cleared_after_request():
    client = TestClient(app)
    client.get('/health')
    assert get_request_id() is None
    assert request_id_var.get() is None


# ── request timing ────────────────────────────────────────────────────────────
#
# Uvicorn's access log has method, path and status but no duration, which left every latency
# question in the beta review unanswerable from production logs. These pin the shape of the line
# that fixes that, and the one property that is a security concern rather than a formatting one.

def test_timing_line_carries_method_path_status_and_duration(caplog):
    with caplog.at_level(logging.INFO, logger='lc_connect.access'):
        TestClient(app).get('/health')

    line = next(r.getMessage() for r in caplog.records if r.name == 'lc_connect.access')
    assert 'GET /health' in line
    assert '-> 200' in line
    assert re.search(r'in \d+\.\d+ms', line), line


def test_timing_line_never_includes_the_query_string(caplog):
    """The one property here that is a security concern, not a formatting preference.

    A path id (`/messages/threads/<uuid>`) is what makes a slow request diagnosable and is fine to
    log. A query string can carry a search term someone typed or a token, and these lines get
    pasted into bug reports.
    """
    with caplog.at_level(logging.INFO, logger='lc_connect.access'):
        TestClient(app).get('/health?token=super-secret&q=someone%27s+name')

    line = next(r.getMessage() for r in caplog.records if r.name == 'lc_connect.access')
    assert 'super-secret' not in line
    assert 'q=' not in line
    assert 'GET /health' in line


def test_slow_requests_log_at_warning(caplog, monkeypatch):
    """Level is how a slow request gets found — filtering by WARNING in Render's log search beats
    reading every line."""
    settings = get_settings()
    monkeypatch.setattr(settings, 'slow_request_ms', 0, raising=False)

    with caplog.at_level(logging.INFO, logger='lc_connect.access'):
        TestClient(app).get('/health')

    record = next(r for r in caplog.records if r.name == 'lc_connect.access')
    assert record.levelno == logging.WARNING
    assert '[slow]' in record.getMessage()


def test_a_failing_request_is_still_timed(caplog):
    """An unhandled error is the most useful thing to have a duration for, so the timing must not
    be lost to the exception path."""
    failing = FastAPI()
    failing.add_middleware(RequestIdMiddleware)

    @failing.get('/boom')
    async def boom():
        raise RuntimeError('kaboom')

    with caplog.at_level(logging.INFO, logger='lc_connect.access'):
        with pytest.raises(RuntimeError):
            TestClient(failing).get('/boom')

    line = next(r.getMessage() for r in caplog.records if r.name == 'lc_connect.access')
    assert 'GET /boom' in line
    assert '-> 500' in line


def test_websocket_handshakes_are_not_timed(caplog):
    """A socket lives for minutes, so its duration would measure how long the app stayed open —
    noise in a log whose whole purpose is per-request latency."""
    with caplog.at_level(logging.INFO, logger='lc_connect.access'):
        try:
            with TestClient(app).websocket_connect('/api/v1/ws') as ws:
                ws.close()
        except Exception:
            pass  # the handshake may be rejected without auth; either way nothing should be timed

    assert [r for r in caplog.records if r.name == 'lc_connect.access'] == []
