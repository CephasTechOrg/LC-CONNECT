"""Supabase 'Send Email' Auth Hook handler — the single place that makes EVERY Supabase auth
email (signup confirmation, password recovery, invite, magic link, email change) go out through
LC Connect's own branded templates via Resend, instead of Supabase's own dashboard-configured
mailer.

Configured once in the Supabase dashboard (Authentication → Hooks → Send Email). Once enabled,
Supabase calls this endpoint INSTEAD of sending anything itself — for every auth action, from
every client. That's what closes the one remaining gap after the admin/employer invite fix: the
mobile app's direct `supabase.auth.signUp()` / `resend()` / `resetPasswordForEmail()` calls never
go through this backend at all, so the only way to override their emails is at the Supabase
project level, not per-call. Zero mobile code changes needed.

Security: Supabase signs every hook request per the Standard Webhooks spec (the same scheme
Svix/Stripe use) — verified here with the `standardwebhooks` package against
`settings.supabase_send_email_hook_secret` (the secret Supabase generates when you enable the
hook). A request that fails verification is rejected before any email is composed or sent.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import HTTPException, Request, status
from standardwebhooks.webhooks import Webhook, WebhookVerificationError

from app import email as email_service
from app.config import settings

logger = logging.getLogger(__name__)


async def verify_and_parse(request: Request) -> dict[str, Any]:
    """Raises HTTPException (503 unconfigured, 401 bad signature) — never returns unverified data."""
    if not settings.supabase_send_email_hook_secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail='Send-email hook is not configured'
        )
    body = await request.body()
    try:
        payload = Webhook(settings.supabase_send_email_hook_secret).verify(body, dict(request.headers))
    except (WebhookVerificationError, ValueError) as exc:
        # `standardwebhooks` raises its own `WebhookVerificationError` for a well-formed-but-
        # mismatched signature, but a malformed one (bad base64, wrong header shape, ...) can
        # surface as a raw `binascii.Error`/`ValueError` instead — fail closed on both, not just
        # the one the library documents, since either way this request cannot be trusted.
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid webhook signature') from exc
    return payload


def send_for_payload(payload: dict[str, Any]) -> None:
    """Always raises HTTPException on failure (400 for a malformed payload, 500 for a send
    failure) — never a bare exception — so the caller (the webhook endpoint) can uniformly turn
    it into Supabase's documented hook-error shape, which blocks the underlying auth action (e.g.
    signup itself fails) rather than silently completing without ever giving the user a way to
    confirm."""
    user = payload.get('user') or {}
    email_data = payload.get('email_data') or {}
    to_email = user.get('email')
    if not to_email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Missing user email in hook payload')

    action_type = email_data.get('email_action_type')
    code = email_data.get('token', '')
    # The plain destination page Supabase was told to return to — deliberately NOT the
    # `/auth/v1/verify?token=...` magic link, which encodes the same single-use token as `code`
    # and would consume it on click, invalidating the code the user is about to type.
    page_url = email_data.get('redirect_to') or None

    try:
        if action_type == 'recovery':
            email_service.send_password_reset_email(to_email, page_url=page_url, code=code)
        elif action_type == 'invite':
            email_service.send_invite_email(to_email, page_url=page_url, code=code, context='admin')
        else:
            # 'signup', 'magiclink', 'email_change', or anything Supabase adds later — all of
            # these are "confirm this address" in spirit, so the signup-confirmation copy fits.
            email_service.send_signup_confirmation_email(to_email, code=code)
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001 — any send failure (Resend down, etc.) must still
        # surface as a clean hook failure, never a bare 500 with no Supabase-recognizable shape.
        logger.exception('send_email_hook: failed to send %s email to %s', action_type, to_email)
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Could not send email') from exc
