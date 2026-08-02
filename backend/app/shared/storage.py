"""Supabase Storage infrastructure (profile image uploads + Blueprint Bond private files).

Cross-cutting infra used by the profiles and scholars features. Kept in the shared kernel so no
feature owns another feature's I/O client.
"""

from __future__ import annotations

import logging
import time
from uuid import UUID

from fastapi import HTTPException, status
from supabase import create_client

from app.config import settings

logger = logging.getLogger(__name__)


class SupabaseStorageService:
    def __init__(self) -> None:
        self.client = None
        if settings.supabase_url and settings.supabase_service_role_key:
            self.client = create_client(settings.supabase_url, settings.supabase_service_role_key)

    def _upload_image(self, prefix: str, name: str, content_type: str, data: bytes) -> str:
        """Replace-and-return a public URL for a sanitized image at `{prefix}/{name}.jpg`.

        Bytes are already sanitized upstream, so the object name is fully server-controlled. The
        deterministic path (+ prior-file removal) means one object per entity — no bucket leak.
        """
        if self.client is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Supabase Storage is not configured')

        bucket = self.client.storage.from_(settings.supabase_profile_bucket)
        path = f'{prefix}/{name}.jpg'
        # Remove any prior image (all extensions — covers pre-sanitizer uploads).
        for ext in ('jpg', 'jpeg', 'png', 'webp'):
            try:
                bucket.remove([f'{prefix}/{name}.{ext}'])
            except Exception:
                pass
        bucket.upload(path=path, file=data, file_options={'content-type': content_type, 'cache-control': '3600'})
        # `?v=<ts>` busts Flutter's Image.network cache after every update.
        return f'{str(bucket.get_public_url(path))}?v={int(time.time())}'

    def upload_profile_image(self, user_id: UUID, content_type: str, data: bytes) -> str:
        return self._upload_image(f'profiles/{user_id}', 'avatar', content_type, data)

    def upload_group_image(self, group_id: UUID, content_type: str, data: bytes) -> str:
        return self._upload_image(f'groups/{group_id}', 'avatar', content_type, data)

    def upload_activity_banner(self, activity_id: UUID, content_type: str, data: bytes) -> str:
        return self._upload_image(f'activities/{activity_id}', 'banner', content_type, data)

    def delete_profile_image(self, user_id: UUID) -> None:
        """Best-effort removal of a user's avatar (all extensions) — used on account deletion.
        Never raises: a storage miss must not block the deletion."""
        if self.client is None:
            return
        bucket = self.client.storage.from_(settings.supabase_profile_bucket)
        for ext in ('jpg', 'jpeg', 'png', 'webp'):
            try:
                bucket.remove([f'profiles/{user_id}/avatar.{ext}'])
            except Exception:
                pass

    # ── Blueprint Bond: private scholar files (headshot / résumé) ───────────────────
    # A separate PRIVATE bucket, never `supabase_profile_bucket` (public). Uploads return only
    # the object *path* — never a URL. Every read goes through `scholar_signed_url`, generated
    # fresh each time, so nothing long-lived-feeling ever gets cached client-side.

    _SCHOLAR_FILE_EXTENSIONS: dict[str, tuple[str, ...]] = {
        'headshot': ('jpg',),
        'resume': ('pdf', 'docx'),
    }

    @staticmethod
    def _scholar_path(user_id: UUID, kind: str, ext: str) -> str:
        return f'{user_id}/{kind}.{ext}'

    def upload_scholar_file(self, user_id: UUID, kind: str, ext: str, content_type: str, data: bytes) -> str:
        """Upload a private scholar file (headshot|resume) and return its object path.

        Replaces any prior file for that (user, kind) across known extensions first — one object
        per (user, kind), same deterministic-path-plus-cleanup shape as `_upload_image`.
        """
        if self.client is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Supabase Storage is not configured')
        bucket = self.client.storage.from_(settings.supabase_scholar_bucket)
        for existing_ext in self._SCHOLAR_FILE_EXTENSIONS.get(kind, ()):
            try:
                bucket.remove([self._scholar_path(user_id, kind, existing_ext)])
            except Exception:
                pass
        path = self._scholar_path(user_id, kind, ext)
        try:
            bucket.upload(path=path, file=data, file_options={'content-type': content_type})
        except HTTPException:
            raise
        except Exception as exc:  # noqa: BLE001 — storage-side failures (missing bucket, outage,
            # quota) must never reach a student as a raw 500 with a vendor stack trace.
            logger.exception(
                'storage: failed to upload %s for %s to bucket %r',
                kind, user_id, settings.supabase_scholar_bucket,
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail='Could not save your file right now. Please try again in a moment.',
            ) from exc
        return path

    def scholar_signed_url(self, path: str, *, expires_in: int) -> str:
        """A fresh, short-lived signed URL for a private scholar file object path."""
        if self.client is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Supabase Storage is not configured')
        bucket = self.client.storage.from_(settings.supabase_scholar_bucket)
        try:
            result = bucket.create_signed_url(path, expires_in)
        except HTTPException:
            raise
        except Exception as exc:  # noqa: BLE001 — same reasoning as `upload_scholar_file`: a
            # storage outage must surface as a clean, retryable message, never a vendor error.
            logger.exception('storage: failed to sign %r in bucket %r', path, settings.supabase_scholar_bucket)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail='Could not open that file right now. Please try again in a moment.',
            ) from exc
        url = result.get('signedURL') or result.get('signedUrl')
        if not url:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Could not generate a signed URL')
        return url

    def scholar_signed_urls(self, paths: list[str], *, expires_in: int) -> dict[str, str]:
        """Sign many object paths in ONE Supabase call — `{path: url}`, missing entries omitted.

        Used by the employer scholar directory so showing N faces costs one round trip instead of
        N. Best-effort by design: a signing failure degrades that card to initials rather than
        failing the whole directory listing.
        """
        if self.client is None or not paths:
            return {}
        try:
            results = self.client.storage.from_(settings.supabase_scholar_bucket).create_signed_urls(
                paths, expires_in
            )
        except Exception:  # noqa: BLE001 — a thumbnail is cosmetic; never break the listing for it
            logger.exception('storage: batch signing failed for %d path(s)', len(paths))
            return {}
        signed: dict[str, str] = {}
        for item in results:
            url = item.get('signedURL') or item.get('signedUrl')
            # Supabase returns the path with a leading slash on some versions; normalise so the
            # caller can look up by the exact path it passed in.
            raw_path = (item.get('path') or '').lstrip('/')
            if url and raw_path:
                signed[raw_path] = url
        return signed

    def ping(self) -> bool:
        """A cheap, real reachability check for the admin dashboard's System Status strip — lists
        buckets (no path/bucket-name assumptions needed), never a cached/assumed value."""
        if self.client is None:
            return False
        try:
            self.client.storage.list_buckets()
            return True
        except Exception:  # noqa: BLE001 — a status check must never itself raise
            logger.exception('storage: ping failed')
            return False

    def delete_scholar_file(self, user_id: UUID, kind: str) -> None:
        """Best-effort removal of a scholar file (all known extensions) — used on account
        deletion. Never raises: a storage miss must not block the deletion."""
        if self.client is None:
            return
        bucket = self.client.storage.from_(settings.supabase_scholar_bucket)
        for ext in self._SCHOLAR_FILE_EXTENSIONS.get(kind, ()):
            try:
                bucket.remove([self._scholar_path(user_id, kind, ext)])
            except Exception:
                pass


storage_service = SupabaseStorageService()
