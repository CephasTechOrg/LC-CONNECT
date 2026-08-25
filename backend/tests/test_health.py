"""Liveness vs readiness probes — DB-free (dependency probes are monkeypatched)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app
from app.shared import health as health_mod


def test_liveness_is_always_ok():
    client = TestClient(app)
    resp = client.get('/health')
    assert resp.status_code == 200
    body = resp.json()
    assert body['status'] == 'ok'
    assert body['service'] == 'lc-connect-api'


def test_readiness_ready_when_database_ok(monkeypatch):
    async def _ok() -> str:
        return 'ok'

    async def _skipped() -> str:
        return 'skipped'

    monkeypatch.setattr(health_mod, 'probe_database', _ok)
    monkeypatch.setattr(health_mod, 'probe_redis', _skipped)

    client = TestClient(app)
    resp = client.get('/health/ready')
    assert resp.status_code == 200
    body = resp.json()
    assert body['status'] == 'ready'
    assert body['checks']['database'] == 'ok'
    assert body['checks']['redis'] == 'skipped'


def test_readiness_503_when_database_down(monkeypatch):
    async def _down() -> str:
        return 'down'

    async def _skipped() -> str:
        return 'skipped'

    monkeypatch.setattr(health_mod, 'probe_database', _down)
    monkeypatch.setattr(health_mod, 'probe_redis', _skipped)

    client = TestClient(app)
    resp = client.get('/health/ready')
    assert resp.status_code == 503
    body = resp.json()
    assert body['status'] == 'not_ready'
    assert body['checks']['database'] == 'down'


def test_readiness_503_when_redis_configured_but_down(monkeypatch):
    """Once REDIS_URL is set, a dead Redis must fail readiness (multi-instance deploy)."""

    async def _ok() -> str:
        return 'ok'

    async def _down() -> str:
        return 'down'

    monkeypatch.setattr(health_mod, 'probe_database', _ok)
    monkeypatch.setattr(health_mod, 'probe_redis', _down)

    client = TestClient(app)
    resp = client.get('/health/ready')
    assert resp.status_code == 503
    assert resp.json()['checks']['redis'] == 'down'


async def test_build_readiness_composes_checks(monkeypatch):
    async def _ok() -> str:
        return 'ok'

    async def _skipped() -> str:
        return 'skipped'

    monkeypatch.setattr(health_mod, 'probe_database', _ok)
    monkeypatch.setattr(health_mod, 'probe_redis', _skipped)

    report = await health_mod.build_readiness()
    assert report.status == 'ready'
    assert report.checks.database == 'ok'
    assert report.checks.redis == 'skipped'
