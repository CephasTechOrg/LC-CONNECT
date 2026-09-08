"""Unit tests for link preview unfurl helpers (no network)."""

from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from app.shared import link_preview as lp

SAMPLE_HTML = """
<!DOCTYPE html>
<html>
<head>
  <title>Fallback Title</title>
  <meta property="og:title" content="Summer Internship" />
  <meta property="og:description" content="Join our team this summer." />
  <meta property="og:site_name" content="Example Careers" />
  <meta property="og:image" content="/images/poster.jpg" />
</head>
<body></body>
</html>
"""


def test_parse_html_preview_reads_og_and_absolutizes_image():
    preview = lp.parse_html_preview(SAMPLE_HTML, base_url='https://jobs.example.com/posting/1')
    assert preview.status == 'ok'
    assert preview.title == 'Summer Internship'
    assert preview.description == 'Join our team this summer.'
    assert preview.site_name == 'Example Careers'
    assert preview.image_url == 'https://jobs.example.com/images/poster.jpg'
    assert preview.domain == 'jobs.example.com'


def test_parse_html_falls_back_to_title_tag():
    html = '<html><head><title>  Plain Title  </title></head></html>'
    preview = lp.parse_html_preview(html, base_url='https://example.com/')
    assert preview.title == 'Plain Title'
    assert preview.domain == 'example.com'


@pytest.mark.parametrize(
    'url',
    [
        'file:///etc/passwd',
        'ftp://example.com/a',
        'http://127.0.0.1/admin',
        'http://10.0.0.5/',
        'http://192.168.1.1/',
        'http://169.254.169.254/latest/meta-data',
        'http://[::1]/',
        'https://user:pass@example.com/',
        'http://localhost:8000/secret',
    ],
)
def test_is_safe_public_url_rejects_dangerous(url: str):
    assert lp.is_safe_public_url(url) is False


def test_is_safe_public_url_accepts_public_ip_literal():
    # 1.1.1.1 is public; no DNS needed for literals.
    assert lp.is_safe_public_url('https://1.1.1.1/cdn-cgi/trace') is True


def test_is_safe_public_url_rejects_hostname_resolving_private():
    fake = [(None, None, None, None, ('10.0.0.8', 0))]
    with patch('app.shared.link_preview.socket.getaddrinfo', return_value=fake):
        assert lp.is_safe_public_url('https://evil.internal.example/') is False


def test_is_safe_public_url_accepts_hostname_resolving_public():
    fake = [(None, None, None, None, ('93.184.216.34', 0))]
    with patch('app.shared.link_preview.socket.getaddrinfo', return_value=fake):
        assert lp.is_safe_public_url('https://example.com/jobs') is True


def test_clear_and_apply_link_preview_on_post():
    post = SimpleNamespace(
        link_preview_domain='x',
        link_preview_site_name='x',
        link_preview_title='x',
        link_preview_description='x',
        link_preview_image_url='x',
        link_preview_fetched_at='x',
        link_preview_status='ok',
    )
    lp.clear_link_preview(post)  # type: ignore[arg-type]
    assert post.link_preview_domain is None
    assert post.link_preview_status is None

    preview = lp.LinkPreview(
        domain='example.com',
        site_name='Example',
        title='Role',
        description='Desc',
        image_url='https://example.com/a.png',
        status='ok',
    )
    lp.apply_link_preview(post, preview)  # type: ignore[arg-type]
    assert post.link_preview_domain == 'example.com'
    assert post.link_preview_title == 'Role'
    assert post.link_preview_status == 'ok'
    assert post.link_preview_fetched_at is not None


@pytest.mark.asyncio
async def test_sync_post_clears_when_url_missing():
    post = SimpleNamespace(
        external_url=None,
        link_preview_domain='old.example',
        link_preview_site_name='Old',
        link_preview_title='Old',
        link_preview_description='Old',
        link_preview_image_url='https://old.example/i.png',
        link_preview_fetched_at='old',
        link_preview_status='ok',
    )
    await lp.sync_post_link_preview(post)  # type: ignore[arg-type]
    assert post.link_preview_domain is None
    assert post.link_preview_status is None


@pytest.mark.asyncio
async def test_sync_post_applies_failed_when_fetch_returns_none(monkeypatch: pytest.MonkeyPatch):
    async def _boom(_url: str):
        return None, None

    monkeypatch.setattr(lp, '_download_html', _boom)
    post = SimpleNamespace(
        external_url='https://example.com/job',
        link_preview_domain=None,
        link_preview_site_name=None,
        link_preview_title=None,
        link_preview_description=None,
        link_preview_image_url=None,
        link_preview_fetched_at=None,
        link_preview_status=None,
    )
    await lp.sync_post_link_preview(post)  # type: ignore[arg-type]
    assert post.link_preview_status == 'failed'
    assert post.link_preview_domain == 'example.com'
    assert post.link_preview_title is None


def test_parse_strips_internal_image_url():
    html = """
    <html><head>
      <meta property="og:title" content="Secret" />
      <meta property="og:image" content="http://127.0.0.1/logo.png" />
    </head></html>
    """
    preview = lp.parse_html_preview(html, base_url='https://example.com/')
    assert preview.title == 'Secret'
    assert preview.image_url is None


def test_link_preview_dict_none_until_attempted():
    post = SimpleNamespace(link_preview_status=None)
    assert lp.link_preview_dict(post) is None  # type: ignore[arg-type]


def test_link_preview_dict_includes_stored_fields():
    fetched = datetime(2026, 9, 7, tzinfo=UTC)
    post = SimpleNamespace(
        link_preview_domain='jobs.example.com',
        link_preview_site_name='Example',
        link_preview_title='Intern',
        link_preview_description='Join us',
        link_preview_image_url='https://jobs.example.com/i.png',
        link_preview_fetched_at=fetched,
        link_preview_status='ok',
    )
    payload = lp.link_preview_dict(post)  # type: ignore[arg-type]
    assert payload == {
        'domain': 'jobs.example.com',
        'site_name': 'Example',
        'title': 'Intern',
        'description': 'Join us',
        'image_url': 'https://jobs.example.com/i.png',
        'fetched_at': fetched,
        'status': 'ok',
    }
