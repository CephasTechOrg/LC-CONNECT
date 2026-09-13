"""Loads the policy documents from `docs/policies/` and caches them in memory.

The markdown files are the single source of truth — they are version-controlled and reviewed
through pull requests, which is the trail a document people are asked to agree to should have.
Serving them from here means a wording fix does not need an App Store release, and the mobile app
and both web portals read the same bytes.
"""

from __future__ import annotations

import logging
import os
from functools import cache
from pathlib import Path

from fastapi import HTTPException, status

from app.shared.policy_versions import CURRENT_POLICY_VERSION, PUBLIC_POLICY_SLUGS

logger = logging.getLogger(__name__)

def _find_default_dir() -> Path:
    """Walk up from this file until `docs/policies` appears.

    Searching beats counting `parents[n]`: the docs sit outside `backend/`, so a fixed index breaks
    silently if this module ever moves, and the failure looks like a missing document rather than a
    wrong path. Returns the best guess even when nothing is found, so the caller's 503 names a real
    path in the log.
    """
    here = Path(__file__).resolve()
    for parent in here.parents:
        candidate = parent / 'docs' / 'policies'
        if candidate.is_dir():
            return candidate
    return here.parents[4] / 'docs' / 'policies'


def policy_dir() -> Path:
    """Where the markdown lives.

    Resolved from this file's location rather than the working directory, so it does not depend on
    where uvicorn was started. `POLICY_DOCS_DIR` overrides it for deployments that relocate the
    docs (a container copying only `backend/`, say).
    """
    override = os.environ.get('POLICY_DOCS_DIR')
    return Path(override) if override else _find_default_dir()


def _title_from(markdown: str, slug: str) -> str:
    """The document's own H1, minus the shared 'LC Connect — ' prefix.

    Falls back to the slug so a missing heading degrades to something readable rather than empty.
    """
    for line in markdown.splitlines():
        if line.startswith('# '):
            return line[2:].removeprefix('LC Connect — ').strip()
    return slug.replace('-', ' ').title()


@cache
def load_document(slug: str) -> dict:
    """One document, cached. Raises 404 for anything not on the allowlist."""
    if slug not in PUBLIC_POLICY_SLUGS:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Policy document not found')

    path = policy_dir() / f'{slug}.md'
    try:
        body = path.read_text(encoding='utf-8')
    except OSError as exc:
        # A deployment that cannot read its own policies is misconfigured, not merely missing a
        # page: the acceptance gate has nothing to show. Loud 503 rather than a silent empty body.
        logger.error('policy document unreadable: %s (%s)', path, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Policy documents are unavailable',
        ) from exc

    return {
        'slug': slug,
        'title': _title_from(body, slug),
        'version': CURRENT_POLICY_VERSION,
        'body': body,
    }


def list_documents() -> dict:
    """Slugs and titles only — the index, without shipping four full documents to render a menu."""
    return {
        'version': CURRENT_POLICY_VERSION,
        'documents': [
            {'slug': doc['slug'], 'title': doc['title']}
            for doc in (load_document(slug) for slug in PUBLIC_POLICY_SLUGS)
        ],
    }


def clear_cache() -> None:
    """Drop the cache. For tests, and for a future reload hook."""
    load_document.cache_clear()
