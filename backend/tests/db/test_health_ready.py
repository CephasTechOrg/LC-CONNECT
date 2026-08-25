"""Readiness probe against a real Postgres (CI + local with test DB)."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


def test_readiness_ok_against_live_postgres(db):
    # `db` fixture proves Postgres is up and the schema is prepared; readiness uses the
    # app engine against DATABASE_URL / same cluster.
    _ = db
    client = TestClient(app)
    resp = client.get('/health/ready')
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body['status'] == 'ready'
    assert body['checks']['database'] == 'ok'
    # Redis not required until Phase 5 — must not fail readiness when unset.
    assert body['checks']['redis'] == 'skipped'
