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


storage_service = SupabaseStorageService()
