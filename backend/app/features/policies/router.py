"""Public policy documents.

Deliberately **unauthenticated**: you have to be able to read the terms before you have an
account, and the signup screen links straight into them. `features/lookups/router.py` is the
existing precedent for a public read-only endpoint.
"""

from __future__ import annotations

from fastapi import APIRouter, Response

from app.features.policies import service
from app.features.policies.schema import PolicyDocument, PolicyIndex

router = APIRouter(prefix='/policies', tags=['policies'])

# These change only when someone edits a markdown file and redeploys, and they are the one thing
# every client fetches before it can do anything. Caching keeps an unauthenticated, unrate-limited
# endpoint from serving the same ~10KB repeatedly to the same device.
_CACHE_CONTROL = 'public, max-age=3600'


@router.get('', response_model=PolicyIndex)
async def list_policies(response: Response) -> PolicyIndex:
    response.headers['Cache-Control'] = _CACHE_CONTROL
    return PolicyIndex.model_validate(service.list_documents())


@router.get('/{slug}', response_model=PolicyDocument)
async def get_policy(slug: str, response: Response) -> PolicyDocument:
    """404 for any slug not on the public allowlist — `docs/policies/` also holds internal notes."""
    document = PolicyDocument.model_validate(service.load_document(slug))
    response.headers['Cache-Control'] = _CACHE_CONTROL
    return document
