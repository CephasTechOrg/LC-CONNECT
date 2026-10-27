"""Chat link-preview endpoint — auth, URL extraction, SSRF-safe unfurl. No network."""

from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user
from app.main import app
from app.shared.link_preview import LinkPreview


async def _dummy_db():
    yield None


@pytest.fixture(autouse=True)
def _clear_overrides():
    yield
    app.dependency_overrides.clear()


def _user():
    return SimpleNamespace(
        id=uuid4(),
        email='student@students.livingstone.edu',
        auth_user_id=uuid4(),
        is_active=True,
        status='active',
        is_verified=True,
        role='student',
    )


def _client() -> TestClient:
    app.dependency_overrides[get_current_user] = lambda: _user()
    app.dependency_overrides[get_db] = _dummy_db
    return TestClient(app)


def test_preview_rejects_text_with_no_url():
    resp = _client().post('/api/v1/messages/link-preview', json={'url': 'not a link'})
    assert resp.status_code == 400
    assert 'http' in resp.json()['detail'].lower()


def test_preview_returns_unfurl_payload():
    fake = LinkPreview(
        domain='jobs.example.com',
        site_name='Example Careers',
        title='Summer Intern',
        description='Join us',
        image_url='https://jobs.example.com/i.png',
        status='ok',
    )
    with patch(
        'app.shared.link_preview.fetch_link_preview',
        new=AsyncMock(return_value=fake),
    ) as fetch:
        resp = _client().post(
            '/api/v1/messages/link-preview',
            json={'url': 'check https://jobs.example.com/posting'},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert body['url'] == 'https://jobs.example.com/posting'
    assert body['title'] == 'Summer Intern'
    assert body['domain'] == 'jobs.example.com'
    assert body['status'] == 'ok'
    assert body['fetched_at'] is not None
    datetime.fromisoformat(body['fetched_at'].replace('Z', '+00:00')).astimezone(UTC)
    fetch.assert_awaited_once()


def test_preview_requires_auth():
    app.dependency_overrides.clear()
    resp = TestClient(app).post(
        '/api/v1/messages/link-preview',
        json={'url': 'https://example.com'},
    )
    assert resp.status_code in {401, 403}
