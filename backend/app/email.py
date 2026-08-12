import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import resend

from app.config import settings


def _send_via_resend(to_email: str, subject: str, text: str, html: str) -> None:
    resend.api_key = settings.resend_api_key
    params: resend.Emails.SendParams = {
        'from': settings.resend_from_email,
        'to': [to_email],
        'subject': subject,
        'text': text,
        'html': html,
    }
    if settings.resend_reply_to:
        params['reply_to'] = settings.resend_reply_to
    resend.Emails.send(params)


def _send_via_smtp(to_email: str, subject: str, text: str, html: str) -> None:
    msg = MIMEMultipart('alternative')
    msg['Subject'] = subject
    msg['From'] = settings.smtp_from
    msg['To'] = to_email
    msg.attach(MIMEText(text, 'plain'))
    msg.attach(MIMEText(html, 'html'))

    ctx = ssl.create_default_context()
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
        server.ehlo()
        if settings.smtp_tls:
            server.starttls(context=ctx)
        server.login(settings.smtp_username, settings.smtp_password)
        server.sendmail(settings.smtp_username, to_email, msg.as_string())


def _send_via_console(to_email: str, subject: str, text: str, _html: str) -> None:
    """Development only — deliberately prints the whole body (that's the point: it's how a dev
    reads the OTP without a mail provider). `_active_provider` refuses to select this in
    production precisely because the body contains invite and password-reset codes."""
    print(f'[EMAIL] To: {to_email} | Subject: {subject}\n{text}')


def _active_provider() -> str:
    p = settings.email_provider.lower()
    if p == 'auto':
        if settings.resend_api_key:
            p = 'resend'
        elif settings.smtp_username and settings.smtp_password:
            p = 'smtp'
        else:
            p = 'console'
    if p == 'console' and settings.is_production:
        # Falling back to console in production would do two silently-bad things at once: print
        # invite/reset codes into the log stream, and "send" mail that never reaches anyone —
        # with no error to notice. Fail loudly instead; a caller turns this into a clean 503.
        raise RuntimeError(
            'Email is not configured in production (no RESEND_API_KEY or SMTP credentials). '
            'Refusing to fall back to console, which would log auth codes and deliver nothing.'
        )
    return p


def _send_email(to_email: str, subject: str, text: str, html: str) -> None:
    provider = _active_provider()
    if provider == 'resend':
        _send_via_resend(to_email, subject, text, html)
    elif provider == 'smtp':
        _send_via_smtp(to_email, subject, text, html)
    else:
        _send_via_console(to_email, subject, text, html)


# ── Public API ─────────────────────────────────────────────────────

def _cta_button(page_url: str | None, label: str) -> str:
    """A plain navigation button, or nothing when no portal URL is configured.

    Deliberately NOT a magic link: `action_link` and the emailed code are two encodings of the
    SAME single-use Supabase token, so shipping both meant clicking the link silently burned the
    code (and vice versa) — a real trap users hit. The button now just opens the page; the code is
    the one and only thing that authenticates.
    """
    if not page_url:
        return ''
    return f"""\
  <p style="text-align:center;margin-bottom:24px">
    <a href="{page_url}"
       style="display:inline-block;padding:14px 28px;background:#4F8FC2;color:#fff;
              text-decoration:none;border-radius:10px;font-weight:700">
      {label}
    </a>
  </p>
"""


def _build_invite_content(page_url: str | None, code: str, context: str) -> tuple[str, str]:
    if context == 'employer':
        heading = "You've been approved as an LC Connect employer partner"
        intro = "Your organization's Blueprint Bond application has been approved."
    else:
        heading = "You've been invited to LC Connect as an admin"
        intro = "You've been invited to help manage the LC Connect platform."

    where = f'Open {page_url} and enter' if page_url else 'Open the portal and enter'
    text = f"""\
{heading}

{intro}

{where} this code to set your password:

    {code}

This code can only be used once and expires shortly. If you weren't expecting this, ignore
this email.
"""
    html = f"""\
<html>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;color:#1F2937">
  <div style="margin-bottom:24px">
    <span style="font-size:22px;font-weight:800;color:#4F8FC2">LC</span>
    <span style="font-size:22px;font-weight:800;color:#111827"> Connect</span>
  </div>
  <p style="margin-bottom:8px;font-weight:700;font-size:18px">{heading}</p>
  <p style="margin-bottom:24px">{intro}</p>
  <p style="font-size:14px;margin-bottom:8px">Enter this code to set your password:</p>
  <div style="font-size:28px;font-weight:700;letter-spacing:6px;
              padding:16px 20px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {code}
  </div>
{_cta_button(page_url, 'Open the portal')}
  <p style="font-size:13px;color:#6B7280">
    This code can only be used once and expires shortly. If you weren't expecting this, you can
    safely ignore this email.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    return text, html


def send_invite_email(to_email: str, *, page_url: str | None, code: str, context: str = 'admin') -> None:
    """The only invite email LC Connect ever sends — Supabase's own mailer/templates are bypassed
    entirely (see `app/shared/supabase_admin.invite_auth_user`, which calls
    `admin.generate_link` instead of `admin.invite_user_by_email` for exactly this reason: full
    control over branding and content, while Supabase still owns the actual auth token/identity).
    `context` is 'admin' or 'employer' — the only two things that ever invite through this path."""
    text, html = _build_invite_content(page_url, code, context)
    subject = (
        "You've been approved — LC Connect employer partner"
        if context == 'employer'
        else "You've been invited to LC Connect"
    )
    _send_email(to_email=to_email, subject=subject, text=text, html=html)


def _build_password_reset_content(page_url: str | None, code: str) -> tuple[str, str]:
    where = f'Open {page_url} and enter' if page_url else 'Open the reset page and enter'
    text = f"""\
Reset your LC Connect password

We received a request to reset your password.

{where} this code to choose a new one:

    {code}

This code can only be used once and expires shortly. If you didn't request this, you can safely
ignore this email — your password will not be changed.
"""
    html = f"""\
<html>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;color:#1F2937">
  <div style="margin-bottom:24px">
    <span style="font-size:22px;font-weight:800;color:#4F8FC2">LC</span>
    <span style="font-size:22px;font-weight:800;color:#111827"> Connect</span>
  </div>
  <p style="margin-bottom:8px;font-weight:700;font-size:18px">Reset your password</p>
  <p style="margin-bottom:24px">We received a request to reset your LC Connect password.</p>
  <p style="font-size:14px;margin-bottom:8px">Enter this code to choose a new password:</p>
  <div style="font-size:28px;font-weight:700;letter-spacing:6px;
              padding:16px 20px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {code}
  </div>
{_cta_button(page_url, 'Open the reset page')}
  <p style="font-size:13px;color:#6B7280">
    This code can only be used once and expires shortly. If you didn't request this, you can
    safely ignore this email — your password will not be changed.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    return text, html


def send_password_reset_email(to_email: str, *, page_url: str | None, code: str) -> None:
    """Same bypass-Supabase's-own-mailer pattern as `send_invite_email` — see
    `app/shared/supabase_admin.request_password_reset`, which calls `admin.generate_link` (type
    'recovery') and hands the code here rather than letting Supabase email it directly."""
    text, html = _build_password_reset_content(page_url, code)
    _send_email(to_email=to_email, subject='Reset your LC Connect password', text=text, html=html)


def _build_signup_confirmation_content(code: str) -> tuple[str, str]:
    """Code-only by design: this one is triggered by the *mobile* app's own signup, so the
    recipient is already sitting in front of the verification screen. There is no web page worth
    linking them to, and a magic link would consume the same token the app is about to ask for."""
    text = f"""\
Confirm your LC Connect account

Welcome to LC Connect! Enter this code in the app to confirm your email address:

    {code}

This code can only be used once and expires shortly. If you didn't create this account, you can
safely ignore this email.
"""
    html = f"""\
<html>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;color:#1F2937">
  <div style="margin-bottom:24px">
    <span style="font-size:22px;font-weight:800;color:#4F8FC2">LC</span>
    <span style="font-size:22px;font-weight:800;color:#111827"> Connect</span>
  </div>
  <p style="margin-bottom:8px;font-weight:700;font-size:18px">Welcome to LC Connect!</p>
  <p style="margin-bottom:24px">Confirm your email address to finish setting up your account.</p>
  <p style="font-size:14px;margin-bottom:8px">Enter this code in the app:</p>
  <div style="font-size:28px;font-weight:700;letter-spacing:6px;
              padding:16px 20px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {code}
  </div>
  <p style="font-size:13px;color:#6B7280">
    This code can only be used once and expires shortly. If you didn't create this account, you
    can safely ignore this email.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    return text, html


def send_branded_email(
    to_email: str,
    *,
    subject: str,
    text: str,
    heading: str,
    intro: str,
    body_html: str = '',
    page_url: str | None = None,
    cta_label: str | None = None,
    closing: str | None = None,
) -> None:
    """Send a message in the standard LC Connect shell (wordmark, heading, intro, footer).

    The auth templates above each hand-roll this shell because they predate it and are load-
    bearing — they are deliberately left alone. New, non-auth mail (see `app/email_notices.py`)
    composes through here instead of copying the markup a sixth time.

    `body_html` is inserted as-is, so every caller is responsible for escaping anything a human
    typed (`email_notices._reason_block` does).
    """
    closing_html = (
        f'  <p style="font-size:13px;color:#6B7280">{closing}</p>\n' if closing else ''
    )
    html_body = f"""\
<html>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;color:#1F2937">
  <div style="margin-bottom:24px">
    <span style="font-size:22px;font-weight:800;color:#4F8FC2">LC</span>
    <span style="font-size:22px;font-weight:800;color:#111827"> Connect</span>
  </div>
  <p style="margin-bottom:8px;font-weight:700;font-size:18px">{heading}</p>
  <p style="margin-bottom:24px">{intro}</p>
{body_html}{_cta_button(page_url, cta_label or 'Open LC Connect')}
{closing_html}  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    _send_email(to_email=to_email, subject=subject, text=text, html=html_body)


def send_signup_confirmation_email(to_email: str, *, code: str) -> None:
    """Covers the mobile app's direct `supabase.auth.signUp()`/`resend()` calls, which never touch
    this backend — see `app/features/auth/email_hook.py` (the Supabase 'Send Email' Auth Hook),
    which is what actually invokes this for those flows."""
    text, html = _build_signup_confirmation_content(code)
    _send_email(to_email=to_email, subject='Confirm your LC Connect account', text=text, html=html)
