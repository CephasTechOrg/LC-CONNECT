"""Supabase Auth admin client (service-role) — used to delete the auth-side user when someone
deletes their LC Connect account, and to invite new admins (Blueprint Bond Phase 3).

Kept in the shared kernel (not owned by a feature) and failure-isolated: if Supabase is
unconfigured or the call fails, neither function raises — the caller decides how to handle a
miss. For `delete_auth_user` a miss is genuinely non-fatal (the local anonymization already
stands; a left-behind auth user can't reach the app anyway since the backend row is inactive).
For `invite_auth_user` a miss is NOT something the caller should silently swallow — inviting an
admin who never gets a real Supabase identity is a real failure — so its callers must check for
`None` and surface a clear error, unlike the delete path.

`invite_auth_user` deliberately uses `admin.generate_link` (which creates/looks up the auth
identity and returns a link + one-time code **without sending any email**), never
`admin.invite_user_by_email` (which would send Supabase's own dashboard-configured template,
outside our control and inconsistent across the admin/employer contexts). LC Connect always sends
its own branded email — `app/email.py`'s `send_invite_email` — over the exact same Resend/SMTP
path already used for the legacy OTP emails. Supabase still owns the actual auth token/identity;
only the email's content and delivery are ours.
"""

from __future__ import annotations

import logging

from supabase import create_client

from app import email as email_service
from app.config import settings

logger = logging.getLogger(__name__)


class AuthUserAlreadyRegistered(Exception):
    """Raised when an invite targets an email that has already completed sign-up.

    Distinct from a generic failure because the remedy is completely different: the person
    doesn't need another invite (Supabase refuses to issue one), they need a password reset.
    Callers must surface that difference rather than reporting a vague "could not send"."""


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


def invite_auth_user(email: str, *, redirect_to: str | None = None, context: str = 'admin') -> str | None:
    """Invite a new Supabase Auth user by email — creates (or resolves) their Supabase identity via
    `generate_link`, then sends our own branded invite email (never Supabase's own template) to set
    their password and enroll in MFA (never a shared or admin-set password). Returns the new auth
    user's id, or `None` if unconfigured or the call failed — never raises; the caller (an admin
    invite endpoint) must treat `None` as a real failure, not swallow it.

    `redirect_to` should point at the *specific* portal's `/accept-invite` page — admin invites and
    employer-approval invites land in two different Next.js apps sharing one Supabase project.
    `context` is 'admin' or 'employer' — only cosmetic (which copy the email uses)."""
    if _client is None:
        logger.warning('supabase_admin: not configured; cannot invite %s', email)
        return None
    try:
        options = {'redirect_to': redirect_to} if redirect_to else {}
        response = _client.auth.admin.generate_link({'type': 'invite', 'email': email, 'options': options})
        email_service.send_invite_email(
            email,
            action_link=response.properties.action_link,
            code=response.properties.email_otp,
            context=context,
        )
        return response.user.id
    except AuthUserAlreadyRegistered:
        raise
    except Exception as exc:  # noqa: BLE001 — the caller decides how to surface this
        # Supabase refuses to issue an invite for an email that already completed sign-up. That
        # is NOT an outage — it means "this person already has an account", which the caller must
        # be able to report precisely (verified against the live API, not assumed).
        if 'already been registered' in str(exc).lower():
            raise AuthUserAlreadyRegistered(email) from exc
        logger.exception('supabase_admin: failed to invite %s', email)
        return None


def get_auth_user_id_by_email(email: str) -> str | None:
    """Resolve an existing Supabase identity by email, or `None`.

    Used to *link* an already-registered person rather than failing an otherwise-legitimate
    action (granting admin, approving an employer) just because they happen to already have an
    LC Connect account — e.g. an employer contact who is also a student."""
    if _client is None:
        return None
    normalized = email.strip().lower()
    try:
        # No get-by-email in the admin API; page through rather than assume page one is enough.
        page = 1
        while page <= 20:
            users = _client.auth.admin.list_users(page=page, per_page=200)
            if not users:
                return None
            for user in users:
                if (user.email or '').lower() == normalized:
                    return user.id
            page += 1
        return None
    except Exception:  # noqa: BLE001 — a lookup miss must never raise into a caller
        logger.exception('supabase_admin: failed to look up auth user for %s', email)
        return None


def request_password_reset(email: str, *, redirect_to: str | None = None) -> bool:
    """Same `generate_link`-then-send-our-own-email pattern as `invite_auth_user`, for
    'recovery' instead of 'invite'. Returns False on any failure (unconfigured, no such account,
    Resend error, ...) — the caller (`POST /auth/forgot-password`) must always report success to
    the client regardless of this return value, to avoid confirming/denying account existence."""
    if _client is None:
        logger.warning('supabase_admin: not configured; cannot send password reset to %s', email)
        return False
    try:
        options = {'redirect_to': redirect_to} if redirect_to else {}
        response = _client.auth.admin.generate_link({'type': 'recovery', 'email': email, 'options': options})
        email_service.send_password_reset_email(
            email, action_link=response.properties.action_link, code=response.properties.email_otp
        )
        return True
    except Exception:  # noqa: BLE001 — best-effort; the caller never surfaces this to the client
        logger.exception('supabase_admin: failed to send password reset to %s', email)
        return False
