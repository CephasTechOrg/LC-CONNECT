"""Supabase Storage infrastructure (profile image uploads).

Cross-cutting infra used by the profiles feature. Kept in the shared kernel so no
feature owns another feature's I/O client.
"""

from __future__ import annotations

import time
from uuid import UUID

from fastapi import HTTPException, status
from supabase import create_client

from app.config import settings


class SupabaseStorageService:
    def __init__(self) -> None:
        self.client = None
        if settings.supabase_url and settings.supabase_service_role_key:
            self.client = create_client(settings.supabase_url, settings.supabase_service_role_key)

    def upload_profile_image(self, user_id: UUID, content_type: str, data: bytes) -> str:
        if self.client is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Supabase Storage is not configured')

        # The bytes are already sanitized to a clean JPEG upstream, so the object name is
        # fully server-controlled (no user-supplied filename/extension reaches storage).
        path = f'profiles/{user_id}/avatar.jpg'

        # Delete any existing avatar (all extensions — covers pre-sanitizer uploads) so the
        # upload never hits a conflict.
        for ext in ('jpg', 'jpeg', 'png', 'webp'):
            try:
                self.client.storage.from_(settings.supabase_profile_bucket).remove(
                    [f'profiles/{user_id}/avatar.{ext}']
                )
            except Exception:
                pass

        self.client.storage.from_(settings.supabase_profile_bucket).upload(
            path=path,
            file=data,
            file_options={'content-type': content_type, 'cache-control': '3600'},
        )

        # Append a timestamp so Flutter's Image.network re-fetches after every update.
        public_url = str(self.client.storage.from_(settings.supabase_profile_bucket).get_public_url(path))
        return f'{public_url}?v={int(time.time())}'


storage_service = SupabaseStorageService()
