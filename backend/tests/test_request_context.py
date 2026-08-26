"""Request correlation id middleware — DB-free."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app
from app.shared.request_context import get_request_id, request_id_var


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
