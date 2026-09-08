"""Server-side link unfurl for campus post `external_url` previews.

Fetches Open Graph / basic HTML meta once on create/update, with SSRF guards.
Never raises into callers — soft-fails to `status='failed'` so publish still works.
"""

from __future__ import annotations

import ipaddress
import logging
import re
import socket
from dataclasses import dataclass
from datetime import UTC, datetime
from html.parser import HTMLParser
from typing import Literal
from urllib.parse import urljoin, urlparse

import httpx

from app.models import CampusPost

logger = logging.getLogger(__name__)

PreviewStatus = Literal['ok', 'failed']

MAX_BODY_BYTES = 512_000
FETCH_TIMEOUT_SECONDS = 5.0
MAX_REDIRECTS = 5
MAX_TITLE_LEN = 200
MAX_DESCRIPTION_LEN = 300
MAX_IMAGE_URL_LEN = 2000
USER_AGENT = 'LC-Connect-LinkPreview/1.0 (+https://livingstone.edu)'

_BLOCKED_HOSTS = frozenset(
    {
        'localhost',
        'metadata.google.internal',
        'metadata.goog',
        'kubernetes.default',
        'kubernetes.default.svc',
    }
)


@dataclass(frozen=True, slots=True)
class LinkPreview:
    domain: str | None
    site_name: str | None
    title: str | None
    description: str | None
    image_url: str | None
    status: PreviewStatus


def clear_link_preview(post: CampusPost) -> None:
    post.link_preview_domain = None
    post.link_preview_site_name = None
    post.link_preview_title = None
    post.link_preview_description = None
    post.link_preview_image_url = None
    post.link_preview_fetched_at = None
    post.link_preview_status = None


def apply_link_preview(post: CampusPost, preview: LinkPreview) -> None:
    post.link_preview_domain = preview.domain
    post.link_preview_site_name = preview.site_name
    post.link_preview_title = preview.title
    post.link_preview_description = preview.description
    post.link_preview_image_url = preview.image_url
    post.link_preview_fetched_at = datetime.now(UTC)
    post.link_preview_status = preview.status


def failed_preview_for(url: str) -> LinkPreview:
    return LinkPreview(
        domain=_domain_of(url),
        site_name=None,
        title=None,
        description=None,
        image_url=None,
        status='failed',
    )


async def sync_post_link_preview(post: CampusPost) -> None:
    """Refresh preview fields from `post.external_url`. Never raises."""
    url = (post.external_url or '').strip()
    if not url:
        clear_link_preview(post)
        return
    try:
        apply_link_preview(post, await fetch_link_preview(url))
    except Exception:  # noqa: BLE001 — preview must never block authoring
        logger.exception('link_preview: unexpected failure for %s', url)
        apply_link_preview(post, failed_preview_for(url))


async def fetch_link_preview(url: str) -> LinkPreview:
    """Fetch and parse preview metadata. Returns `failed` on any soft error."""
    final_url, html = await _download_html(url)
    if html is None:
        return failed_preview_for(url)
    meta = parse_html_preview(html, base_url=final_url or url)
    domain = _domain_of(final_url or url)
    if not meta.title and not meta.site_name and not meta.image_url and not meta.description:
        return LinkPreview(
            domain=domain,
            site_name=None,
            title=None,
            description=None,
            image_url=None,
            status='failed',
        )
    return LinkPreview(
        domain=domain,
        site_name=_clip(meta.site_name, MAX_TITLE_LEN),
        title=_clip(meta.title, MAX_TITLE_LEN),
        description=_clip(meta.description, MAX_DESCRIPTION_LEN),
        image_url=_clip(meta.image_url, MAX_IMAGE_URL_LEN),
        status='ok',
    )


def is_safe_public_url(url: str) -> bool:
    """Reject non-http(s), credentials-in-URL, blocked hosts, and non-global IPs."""
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    if parsed.scheme not in ('http', 'https'):
        return False
    if parsed.username is not None or parsed.password is not None:
        return False
    host = parsed.hostname
    if not host or len(host) > 253:
        return False
    if host.lower().rstrip('.') in _BLOCKED_HOSTS:
        return False
    # Literal IPs in the URL must be public before we even resolve DNS.
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        literal = None
    if literal is not None and not _ip_is_public(literal):
        return False
    return _hostname_resolves_public(host)


def parse_html_preview(html: str, *, base_url: str) -> LinkPreview:
    """Extract OG / Twitter / basic title tags from an HTML document (no network)."""
    parser = _MetaParser()
    try:
        parser.feed(html)
        parser.close()
    except Exception:  # noqa: BLE001 — broken HTML still yields whatever we collected
        logger.debug('link_preview: HTML parse error', exc_info=True)

    og = parser.og
    title = (
        og.get('og:title')
        or og.get('twitter:title')
        or parser.title
    )
    description = (
        og.get('og:description')
        or og.get('twitter:description')
        or og.get('description')
    )
    site_name = og.get('og:site_name')
    image_raw = og.get('og:image') or og.get('twitter:image') or og.get('twitter:image:src')
    image_url = _absolutize(image_raw, base_url) if image_raw else None
    if image_url and not is_safe_preview_asset_url(image_url):
        # Don't surface a preview image that points at an obvious internal host.
        image_url = None

    return LinkPreview(
        domain=_domain_of(base_url),
        site_name=_clip(site_name, MAX_TITLE_LEN),
        title=_clip(title, MAX_TITLE_LEN),
        description=_clip(description, MAX_DESCRIPTION_LEN),
        image_url=_clip(image_url, MAX_IMAGE_URL_LEN),
        status='ok',
    )


def is_safe_preview_asset_url(url: str) -> bool:
    """Lightweight URL check for og:image (no DNS — avoid rejecting valid CDNs offline)."""
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    if parsed.scheme not in ('http', 'https'):
        return False
    if parsed.username is not None or parsed.password is not None:
        return False
    host = parsed.hostname
    if not host or len(host) > 253:
        return False
    if host.lower().rstrip('.') in _BLOCKED_HOSTS:
        return False
    try:
        literal = ipaddress.ip_address(host)
    except ValueError:
        return True
    return _ip_is_public(literal)


# ── internals ──────────────────────────────────────────────────────────────────


class _MetaParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.og: dict[str, str] = {}
        self.title: str | None = None
        self._in_title = False
        self._title_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        lower = tag.lower()
        if lower == 'title':
            self._in_title = True
            return
        if lower != 'meta':
            return
        attr = {k.lower(): (v or '') for k, v in attrs if k}
        name = (attr.get('property') or attr.get('name') or '').strip().lower()
        content = (attr.get('content') or '').strip()
        if name and content and name not in self.og:
            self.og[name] = content

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() == 'title' and self._in_title:
            self._in_title = False
            text = ''.join(self._title_parts).strip()
            if text and not self.title:
                self.title = text

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self._title_parts.append(data)


async def _download_html(url: str) -> tuple[str | None, str | None]:
    if not is_safe_public_url(url):
        logger.info('link_preview: rejected unsafe url %s', url)
        return None, None

    current = url
    try:
        async with httpx.AsyncClient(
            timeout=FETCH_TIMEOUT_SECONDS,
            follow_redirects=False,
            headers={'User-Agent': USER_AGENT, 'Accept': 'text/html,application/xhtml+xml'},
        ) as client:
            for _ in range(MAX_REDIRECTS + 1):
                if not is_safe_public_url(current):
                    return None, None
                response = await client.get(current)
                if response.status_code in {301, 302, 303, 307, 308}:
                    location = response.headers.get('location')
                    if not location:
                        return None, None
                    current = urljoin(current, location)
                    continue
                if response.status_code >= 400:
                    return None, None
                content_type = (response.headers.get('content-type') or '').lower()
                if 'html' not in content_type and 'text/plain' not in content_type:
                    # Some sites omit content-type; still try if body looks like HTML.
                    peek = response.content[:200].lstrip().lower()
                    if not (peek.startswith(b'<!doctype') or peek.startswith(b'<html') or b'<head' in peek):
                        return current, None
                body = response.content[:MAX_BODY_BYTES]
                charset = _charset_from_content_type(content_type) or 'utf-8'
                try:
                    return current, body.decode(charset, errors='replace')
                except LookupError:
                    return current, body.decode('utf-8', errors='replace')
    except httpx.HTTPError:
        logger.info('link_preview: fetch failed for %s', url, exc_info=True)
        return None, None
    return None, None


def _hostname_resolves_public(host: str) -> bool:
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    if not infos:
        return False
    for info in infos:
        raw = info[4][0]
        try:
            ip = ipaddress.ip_address(raw)
        except ValueError:
            return False
        if not _ip_is_public(ip):
            return False
    return True


def _ip_is_public(ip: ipaddress.IPv4Address | ipaddress.IPv6Address) -> bool:
    # `is_global` excludes private, loopback, link-local, multicast, and reserved ranges.
    return bool(ip.is_global)


def _domain_of(url: str) -> str | None:
    try:
        host = urlparse(url).hostname
    except ValueError:
        return None
    if not host:
        return None
    return host.lower().rstrip('.')


def _absolutize(maybe_relative: str, base_url: str) -> str | None:
    raw = maybe_relative.strip()
    if not raw:
        return None
    try:
        return urljoin(base_url, raw)
    except ValueError:
        return None


def _clip(value: str | None, limit: int) -> str | None:
    if value is None:
        return None
    cleaned = re.sub(r'\s+', ' ', value).strip()
    if not cleaned:
        return None
    if len(cleaned) <= limit:
        return cleaned
    return cleaned[: limit - 1].rstrip() + '…'


def _charset_from_content_type(content_type: str) -> str | None:
    match = re.search(r'charset=([^\s;]+)', content_type, flags=re.IGNORECASE)
    if not match:
        return None
    return match.group(1).strip('\'"')
