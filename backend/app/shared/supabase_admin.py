"""Supabase Auth admin client (service-role) — used to delete the auth-side user when someone
deletes their LC Connect account, and to invite new admins (Blueprint Bond Phase 3).

Kept in the shared kernel (not owned by a feature) and failure-isolated: if Supabase is
unconfigured or the call fails, neither function raises — the caller decides how to handle a
miss. For `delete_auth_user` a miss is genuinely non-fatal (the local anonymization already
stands; a left-behind auth user can't reach the app anyway since the backend row is inactive).
For `invite_auth_user` a miss is NOT something the caller should silently swallow — inviting an
admin who never gets a real Supabase identity is a real failure — so its callers must check for
`None` and surface a clear error, unlike the delete path.
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


def invite_auth_user(email: str) -> str | None:
    """Invite a new Supabase Auth user by email — sends them a real invite email to set their own
    password and enroll in MFA (never a shared or admin-set password). Returns the new auth
    user's id, or `None` if unconfigured or the call failed — never raises; the caller (an admin
    invite endpoint) must treat `None` as a real failure, not swallow it."""
    if _client is None:
        logger.warning('supabase_admin: not configured; cannot invite %s', email)
        return None
    try:
        response = _client.auth.admin.invite_user_by_email(email)
        return response.user.id
    except Exception:  # noqa: BLE001 — the caller decides how to surface this; we just never raise here
        logger.exception('supabase_admin: failed to invite %s', email)
        return None
