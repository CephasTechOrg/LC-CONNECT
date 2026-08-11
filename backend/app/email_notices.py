"""Decision-outcome emails — the "somebody reviewed your thing" notices.

Separate from `app/email.py`, which owns *auth* email (invite codes, password reset, signup
confirmation) and is the only thing the Supabase send-email hook drives. These are ordinary
product notifications: an admin made a decision, and the person it affects has to hear about it
somewhere other than an audit log.

Every send here is **failure-isolated by the caller** — the decision is already committed by the
time we email, so a Resend outage must never roll back an approval or make an admin think their
click failed. Callers use `send_quietly`.
"""

from __future__ import annotations

import html
import logging

from app.email import send_branded_email

logger = logging.getLogger(__name__)


def send_quietly(fn, *args, **kwargs) -> bool:
    """Run an email send, swallowing any failure. Returns True if it went out.

    The decision these emails report is already committed, so raising here would turn a mail
    outage into a failed admin action (or worse, a rolled-back approval). Log loudly, carry on —
    the audit log is still the source of truth for what was decided.
    """
    try:
        fn(*args, **kwargs)
        return True
    except Exception:  # noqa: BLE001 — an email failure must never break the decision it reports
        logger.exception('email_notices: failed to send %s', getattr(fn, '__name__', fn))
        return False


def _reason_block(review_note: str | None) -> str:
    """The reviewer's note, escaped.

    `review_note` is free text an admin typed into the portal. It is the genuinely useful part of
    a rejection, so it goes out verbatim — but it lands inside an HTML document, so it must be
    escaped or a stray `<` (let alone a pasted tag) corrupts or injects into the mail body.
    """
    if not review_note or not review_note.strip():
        return ''
    return f"""\
  <p style="font-size:14px;margin-bottom:8px;color:#6B7280">Note from the reviewer:</p>
  <div style="padding:14px 18px;background:#F7F9FC;border-left:3px solid #4F8FC2;
              border-radius:6px;margin-bottom:24px;white-space:pre-wrap">{html.escape(review_note.strip())}</div>
"""


def _decision_email(
    to_email: str,
    *,
    subject: str,
    heading: str,
    intro: str,
    review_note: str | None = None,
    page_url: str | None = None,
    cta_label: str | None = None,
    closing: str | None = None,
) -> None:
    note_text = f'\n\nNote from the reviewer:\n\n    {review_note.strip()}\n' if review_note and review_note.strip() else ''
    where = f'\n\nOpen {page_url}\n' if page_url else ''
    text = f'{heading}\n\n{intro}\n{note_text}{where}\n{closing or ""}\n'
    send_branded_email(
        to_email,
        subject=subject,
        text=text,
        heading=heading,
        intro=intro,
        body_html=_reason_block(review_note),
        page_url=page_url,
        cta_label=cta_label,
        closing=closing,
    )


# ── admin access ───────────────────────────────────────────────────────────────────

def send_admin_access_granted_email(to_email: str, *, portal_url: str | None) -> None:
    """For someone promoted to admin who ALREADY had an LC Connect account.

    That path never sends a Supabase invite (there is no new identity to create), so without this
    the only signal is an in-app notification that renders in the mobile app only — invisible to
    anyone who works from the admin portal or hasn't installed the app.
    """
    _decision_email(
        to_email,
        subject="You've been granted admin access to LC Connect",
        heading="You've been granted admin access",
        intro=(
            'An administrator has given your existing LC Connect account admin access. '
            'Sign in with the email and password you already use — there is no new account to set up.'
        ),
        page_url=portal_url,
        cta_label='Open the Admin Portal',
        closing=(
            "You'll be asked to set up two-factor authentication the first time you sign in; "
            'admin actions require it.'
        ),
    )


# ── campus position review ─────────────────────────────────────────────────────────

_POSITION_COPY = {
    'approved': (
        'Your campus position has been verified',
        'Your campus position has been verified',
        'Staff features are now unlocked for your account: you can publish to the Campus Hub, '
        'message students directly, and see staff announcements.',
    ),
    'rejected': (
        'About your campus position request',
        'Your campus position was not verified',
        'An administrator reviewed your campus position and could not verify it. '
        'You can update the details in the app and submit again.',
    ),
    'revoked': (
        'Your campus position has been revoked',
        'Your campus position has been revoked',
        'Your verified campus position has been revoked, so staff features — publishing, staff '
        'messaging, and staff announcements — are no longer available on your account.',
    ),
}


def send_position_decision_email(to_email: str, *, outcome: str, review_note: str | None) -> None:
    """`outcome` is approved | rejected | revoked — the three states an admin can move a
    position into. Anything else is a programming error and sends nothing."""
    copy = _POSITION_COPY.get(outcome)
    if copy is None:
        logger.error('email_notices: unknown position outcome %r; no email sent', outcome)
        return
    subject, heading, intro = copy
    _decision_email(to_email, subject=subject, heading=heading, intro=intro, review_note=review_note)


# ── employer organization review ───────────────────────────────────────────────────

def send_employer_rejected_email(to_email: str, *, review_note: str | None) -> None:
    """Approval already emails the branded invite (`invite_auth_user`); rejection sent nothing at
    all, leaving the organization's contact waiting indefinitely."""
    _decision_email(
        to_email,
        subject='About your LC Connect employer application',
        heading='Your employer application was not approved',
        intro=(
            'Thank you for your interest in partnering with Livingstone College through LC Connect. '
            'After review, your organization was not approved at this time.'
        ),
        review_note=review_note,
        closing='If you believe this was a mistake, reply to this email and we will take another look.',
    )
