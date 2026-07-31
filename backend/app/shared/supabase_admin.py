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


def ping() -> bool:
    """A cheap, real reachability check for the admin dashboard's System Status strip — the
    smallest possible admin call (one user, page one), never a cached/assumed value."""
    if _client is None:
        return False
    try:
        _client.auth.admin.list_users(page=1, per_page=1)
        return True
    except Exception:  # noqa: BLE001 — a status check must never itself raise
        logger.exception('supabase_admin: ping failed')
        return False


def invite_auth_user(email: str, *, redirect_to: str | None = None) -> str | None:
    """Invite a new Supabase Auth user by email — sends them a real invite email to set their own
    password and enroll in MFA (never a shared or admin-set password). Returns the new auth
    user's id, or `None` if unconfigured or the call failed — never raises; the caller (an admin
    invite endpoint) must treat `None` as a real failure, not swallow it.

    `redirect_to` should point at the *specific* portal's `/accept-invite` page — admin invites and
    employer-approval invites land in two different Next.js apps sharing one Supabase project, so
    leaving this unset would send both through the Supabase dashboard's single shared default Site
    URL, which can only be correct for one of them."""
    if _client is None:
        logger.warning('supabase_admin: not configured; cannot invite %s', email)
        return None
    try:
        options = {'redirect_to': redirect_to} if redirect_to else None
        response = _client.auth.admin.invite_user_by_email(email, options=options)
        return response.user.id
    except Exception:  # noqa: BLE001 — the caller decides how to surface this; we just never raise here
        logger.exception('supabase_admin: failed to invite %s', email)
        return None
