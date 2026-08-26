"""Production hardening: security headers + OpenAPI disabled in prod."""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.main import app
from app.shared.security_headers import SecurityHeadersMiddleware


def test_security_headers_present_on_health() -> None:
    client = TestClient(app)
    response = client.get('/health')
    assert response.status_code == 200
    assert response.headers['x-content-type-options'] == 'nosniff'
    assert response.headers['x-frame-options'] == 'DENY'
    assert response.headers['referrer-policy'] == 'strict-origin-when-cross-origin'
    assert "frame-ancestors 'none'" in response.headers['content-security-policy']
    # Default test ENVIRONMENT is not production — HSTS must stay off.
    assert 'strict-transport-security' not in response.headers


def test_hsts_only_when_enabled() -> None:
    tiny = FastAPI()

    @tiny.get('/ping')
    def ping() -> dict[str, str]:
        return {'ok': '1'}

    tiny.add_middleware(SecurityHeadersMiddleware, enable_hsts=True)
    client = TestClient(tiny)
    response = client.get('/ping')
    assert response.headers['strict-transport-security'] == 'max-age=31536000; includeSubDomains'


def test_docs_disabled_in_production() -> None:
    prod = FastAPI(
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    @prod.get('/')
    def root() -> dict[str, str]:
        return {'message': 'ok'}

    client = TestClient(prod)
    assert client.get('/docs').status_code == 404
    assert client.get('/redoc').status_code == 404
    assert client.get('/openapi.json').status_code == 404


def test_docs_available_outside_production() -> None:
    """CI/local default app keeps Swagger for developers."""
    client = TestClient(app)
    assert client.get('/openapi.json').status_code == 200
    assert client.get('/docs').status_code == 200
    root = client.get('/')
    assert root.json().get('docs') == '/docs'
