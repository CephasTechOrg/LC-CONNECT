"""Honors attendance feature flag + status route."""

from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


def test_honors_attendance_status_disabled_by_default():
    client = TestClient(app)
    response = client.get('/api/v1/attendance/honors/status')
    assert response.status_code == 200
    assert response.json() == {'enabled': False}


def test_honors_attendance_status_reflects_flag(monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, 'honors_attendance_enabled', True)
    client = TestClient(app)
    response = client.get('/api/v1/attendance/honors/status')
    assert response.status_code == 200
    assert response.json() == {'enabled': True}
