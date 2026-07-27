"""Supabase Auth admin client (service-role) — used to delete the auth-side user when someone
deletes their LC Connect account.

Kept in the shared kernel (not owned by a feature) and failure-isolated: if Supabase is
unconfigured or the call fails, the local anonymization still stands and the caller decides how
to handle a non-fatal miss. A left-behind auth user can't reach the app anyway — the backend row
is anonymized (is_active=False), so their token is rejected — but we log it for manual cleanup.
"""

from __future__ import annotations

import logging

from supabase import create_client

from app.config import settings

logger = logging.getLogger(__name__)

_client = None
if settings.supabase_url and settings.supabase_service_role_key:
    _client = create_client(settings.supabase_url, settings.supabase_service_role_key)


def delete_auth_user(auth_user_id: str) -> bool:
    """Delete the Supabase Auth user by id (frees the email for re-registration). Returns True on
    success, False if unconfigured or the call failed — never raises."""
    if _client is None:
        logger.warning('supabase_admin: not configured; skipping auth delete for %s', auth_user_id)
        return False
    try:
        _client.auth.admin.delete_user(auth_user_id)
        return True
    except Exception:  # noqa: BLE001 — best-effort; deletion must not be blocked by an auth-side error
        logger.exception('supabase_admin: failed to delete auth user %s (needs manual cleanup)', auth_user_id)
        return False
