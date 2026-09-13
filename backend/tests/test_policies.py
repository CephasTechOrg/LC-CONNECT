"""Public policy documents, and the acceptance-version logic that gates the app.

DB-free: the document service reads files, and the claims logic is a pure function.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.features.auth.service import _accepted_version_from_claims, _sync_policy_acceptance
from app.features.policies import service
from app.main import app
from app.shared.policy_versions import (
    CURRENT_POLICY_VERSION,
    PUBLIC_POLICY_SLUGS,
    REQUIRED_FOR_APP,
)


@pytest.fixture(autouse=True)
def _clear_cache():
    service.clear_cache()
    yield
    service.clear_cache()


def _claims(metadata):
    return SimpleNamespace(raw={'user_metadata': metadata})


# ── Serving the documents ─────────────────────────────────────────────────────

def test_every_public_slug_resolves_to_a_real_file():
    """The allowlist and the filesystem must agree, or the acceptance gate has nothing to show."""
    for slug in PUBLIC_POLICY_SLUGS:
        doc = service.load_document(slug)
        assert doc['body'].strip(), f'{slug} is empty'
        assert doc['title'], f'{slug} has no title'
        assert doc['version'] == CURRENT_POLICY_VERSION


def test_title_strips_the_shared_prefix():
    assert service.load_document('terms-of-service')['title'] == 'Terms of Service'
    assert service.load_document('privacy-policy')['title'] == 'Privacy Policy'


def test_internal_documents_are_not_served():
    """`docs/policies/` also holds working notes. An allowlist is what keeps a stray filename from
    publishing the coverage audit or the decisions register."""
    for slug in ('README', 'feature-policy-coverage', 'decisions-made', 'implementation-plan'):
        with pytest.raises(HTTPException) as exc:
            service.load_document(slug)
        assert exc.value.status_code == 404


def test_served_documents_carry_nothing_internal():
    """Guards the mistake this nearly shipped with: the employer agreement had an internal gaps
    analysis at the bottom, which would have been served to the employers it constrains."""
    for slug in PUBLIC_POLICY_SLUGS:
        body = service.load_document(slug)['body']
        for leak in ('Notes for us', '[DECIDE]', 'not for employers'):
            assert leak not in body, f'{slug} contains internal marker {leak!r}'


def test_index_lists_every_document_without_bodies():
    index = service.list_documents()
    assert index['version'] == CURRENT_POLICY_VERSION
    assert [d['slug'] for d in index['documents']] == list(PUBLIC_POLICY_SLUGS)
    assert all('body' not in d for d in index['documents'])


def test_the_two_app_policies_are_public():
    """What the signup checkbox links to must be readable without a token."""
    assert set(REQUIRED_FOR_APP) <= set(PUBLIC_POLICY_SLUGS)


# ── Reachable without a token ─────────────────────────────────────────────────

def test_policies_are_readable_with_no_authentication():
    """You have to be able to read the terms before you have an account to agree with."""
    client = TestClient(app)
    assert client.get('/api/v1/policies').status_code == 200
    for slug in REQUIRED_FOR_APP:
        response = client.get(f'/api/v1/policies/{slug}')
        assert response.status_code == 200, slug
        assert response.json()['slug'] == slug


def test_unknown_slug_is_404_not_500():
    client = TestClient(app)
    assert client.get('/api/v1/policies/not-a-policy').status_code == 404


def test_path_traversal_does_not_escape_the_allowlist():
    client = TestClient(app)
    for attempt in ('../README', '..%2FREADME', 'terms-of-service/../../README'):
        assert client.get(f'/api/v1/policies/{attempt}').status_code in (404, 400)


# ── Acceptance version from signup metadata ───────────────────────────────────

def test_version_is_read_from_signup_metadata():
    assert _accepted_version_from_claims(_claims({'policies_accepted_version': 1})) == 1
    assert _accepted_version_from_claims(_claims({'policies_accepted_version': '1'})) == 1


def test_missing_or_junk_metadata_means_not_accepted():
    for metadata in ({}, {'policies_accepted_version': None}, {'policies_accepted_version': 'yes'},
                     {'policies_accepted_version': 0}, {'policies_accepted_version': True}):
        assert _accepted_version_from_claims(_claims(metadata)) == 0


def test_a_claimed_future_version_is_clamped():
    """The security-relevant case. Supabase user metadata is client-writable, so an untampered
    read would let someone claim version 9999 and never be gated again — including by a future
    policy they have not seen."""
    assert _accepted_version_from_claims(
        _claims({'policies_accepted_version': 9999})
    ) == CURRENT_POLICY_VERSION


def test_acceptance_only_moves_forward():
    """A stale client omitting the metadata must not un-accept someone, and re-login must not
    reset an acceptance recorded via POST /auth/accept-policies."""
    user = SimpleNamespace(policies_accepted_version=1, policies_accepted_at='already-set')
    _sync_policy_acceptance(user, _claims({}))
    assert user.policies_accepted_version == 1
    assert user.policies_accepted_at == 'already-set'


def test_acceptance_is_recorded_with_a_timestamp():
    user = SimpleNamespace(policies_accepted_version=0, policies_accepted_at=None)
    _sync_policy_acceptance(user, _claims({'policies_accepted_version': 1}))
    assert user.policies_accepted_version == 1
    assert user.policies_accepted_at is not None


# ── The cross-language contract ───────────────────────────────────────────────

def test_signup_metadata_key_matches_the_mobile_client():
    """The one silent-failure risk in the whole feature.

    The app writes the accepted version into Supabase signup metadata under a string key; this
    backend reads it back out by the same string. A typo on either side is invisible — signup
    succeeds, bootstrap finds nothing, and every user who signs up is gated forever with no error
    anywhere. Nothing else in the stack would catch it, so it is asserted across the two files.
    """
    from pathlib import Path

    key = 'policies_accepted_version'
    backend = Path('app/features/auth/service.py').read_text()
    assert f"metadata.get('{key}')" in backend

    dart = Path('../mobile/lib/features/auth/providers/auth_provider.dart').read_text()
    assert f"'{key}':" in dart, 'mobile must send the key the backend reads'


def test_policy_documents_are_cacheable():
    """Unauthenticated, unrate-limited, and ~10KB a piece — they should not be re-fetched on
    every app launch."""
    client = TestClient(app)
    for path in ('/api/v1/policies', '/api/v1/policies/terms-of-service'):
        response = client.get(path)
        assert response.status_code == 200
        assert 'max-age' in response.headers.get('cache-control', ''), path


# ── Employer Agreement ────────────────────────────────────────────────────────

def _employer_ctx(*, accepted_version: int):
    account = SimpleNamespace(
        email='hr@example.com',
        display_name='HR',
        agreement_accepted_version=accepted_version,
        agreement_accepted_at=None,
    )
    org = SimpleNamespace(id='org-1', name='Example Corp', status='approved')
    return SimpleNamespace(account=account, organization=org)


async def test_agreed_employer_guard_blocks_until_accepted():
    """The guard that makes the agreement real rather than decorative.

    Scholar data and opportunity submission sit behind this. Without it an approved employer
    holding a valid token could skip the portal's gate screen and still read résumés — the same
    reason the mobile bootstrap check exists alongside the signup checkbox.
    """
    from app.features.employers.auth import require_agreed_employer

    with pytest.raises(HTTPException) as exc:
        await require_agreed_employer(_employer_ctx(accepted_version=0))
    assert exc.value.status_code == 403
    assert 'Employer Agreement' in exc.value.detail


async def test_agreed_employer_guard_allows_a_current_acceptance():
    from app.features.employers.auth import require_agreed_employer
    from app.shared.policy_versions import CURRENT_EMPLOYER_AGREEMENT_VERSION

    ctx = _employer_ctx(accepted_version=CURRENT_EMPLOYER_AGREEMENT_VERSION)
    assert await require_agreed_employer(ctx) is ctx


async def test_a_stale_employer_acceptance_is_blocked():
    """Raising the agreement version must re-prompt every partner, not just new ones."""
    from app.features.employers.auth import require_agreed_employer
    from app.shared.policy_versions import CURRENT_EMPLOYER_AGREEMENT_VERSION

    stale = _employer_ctx(accepted_version=CURRENT_EMPLOYER_AGREEMENT_VERSION - 1)
    with pytest.raises(HTTPException):
        await require_agreed_employer(stale)


def test_scholar_routes_sit_behind_the_agreement():
    """Asserted on the wiring, because a new scholar route added with the wrong dependency is
    exactly how student résumés would quietly become reachable without an agreement."""
    from pathlib import Path

    source = Path('app/features/employers/router.py').read_text()
    import re

    for chunk in re.split(r'(?=@router\.)', source):
        if not chunk.startswith('@router.'):
            continue
        path = re.search(r"@router\.\w+\(\s*'?([^',\n]*)", chunk).group(1)
        if path.startswith('/scholars') or path == '/opportunities':
            assert 'require_agreed_employer' in chunk, f'{path} must require the agreement'
        # /me must NOT require it, or the portal cannot discover that it needs to show the gate.
        if path == '/me':
            assert 'require_agreed_employer' not in chunk


def test_the_two_version_constants_are_independent():
    """Bumping the student policies must not re-prompt employers, and vice versa."""
    from pathlib import Path

    source = Path('app/shared/policy_versions.py').read_text()
    assert 'CURRENT_POLICY_VERSION = ' in source
    assert 'CURRENT_EMPLOYER_AGREEMENT_VERSION = ' in source
    assert 'CURRENT_EMPLOYER_AGREEMENT_VERSION = CURRENT_POLICY_VERSION' not in source
