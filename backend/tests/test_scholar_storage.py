"""Private scholar-file storage (headshot / résumé).

Written after a production incident: the `scholar-private` bucket had never actually been
created in Supabase, so *every* upload failed — and the failure surfaced as a raw vendor
`StorageApiError` (an unhandled 500 with a stack trace) rather than anything a student could
act on. These lock the error contract so a storage-side problem always degrades to a clean,
retryable message.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.shared.storage import SupabaseStorageService


class _Boom:
    """Stands in for supabase-py raising its own error type from deep inside the client."""

    def __init__(self, exc: Exception):
        self._exc = exc

    def upload(self, **_kwargs):
        raise self._exc

    def create_signed_url(self, *_args, **_kwargs):
        raise self._exc

    def remove(self, *_args, **_kwargs):
        raise self._exc


def _service_with(bucket) -> SupabaseStorageService:
    service = SupabaseStorageService()
    service.client = type('C', (), {'storage': type('S', (), {'from_': staticmethod(lambda _n: bucket)})()})()
    return service


def test_upload_missing_bucket_is_503_not_a_raw_vendor_error():
    """The exact production failure: bucket not found -> must be a clean 503, never a 500."""
    service = _service_with(_Boom(Exception("{'statusCode': 404, 'error': Bucket not found}")))
    with pytest.raises(HTTPException) as exc:
        service.upload_scholar_file(uuid4(), 'resume', 'pdf', 'application/pdf', b'%PDF-1.4')
    assert exc.value.status_code == 503
    assert 'Bucket not found' not in exc.value.detail  # vendor internals never reach the student
    assert 'try again' in exc.value.detail.lower()


def test_signed_url_storage_failure_is_503_not_a_raw_vendor_error():
    service = _service_with(_Boom(Exception('some vendor blowup')))
    with pytest.raises(HTTPException) as exc:
        service.scholar_signed_url('someone/resume.pdf', expires_in=60)
    assert exc.value.status_code == 503
    assert 'vendor blowup' not in exc.value.detail
    assert 'try again' in exc.value.detail.lower()


def test_upload_unconfigured_client_is_503():
    service = SupabaseStorageService()
    service.client = None
    with pytest.raises(HTTPException) as exc:
        service.upload_scholar_file(uuid4(), 'headshot', 'jpg', 'image/jpeg', b'x')
    assert exc.value.status_code == 503


def test_signed_url_unconfigured_client_is_503():
    service = SupabaseStorageService()
    service.client = None
    with pytest.raises(HTTPException) as exc:
        service.scholar_signed_url('p', expires_in=60)
    assert exc.value.status_code == 503


def test_scholar_paths_are_namespaced_per_user():
    """One object per (user, kind): a deterministic path means a re-upload replaces rather than
    accumulating, and no user's path can collide with another's."""
    a, b = uuid4(), uuid4()
    assert SupabaseStorageService._scholar_path(a, 'resume', 'pdf') == f'{a}/resume.pdf'
    assert SupabaseStorageService._scholar_path(a, 'resume', 'pdf') != SupabaseStorageService._scholar_path(
        b, 'resume', 'pdf'
    )


def test_delete_never_raises_even_when_storage_errors():
    """Account deletion must not be blocked by a storage hiccup."""
    service = _service_with(_Boom(Exception('storage down')))
    service.delete_scholar_file(uuid4(), 'resume')  # must not raise
