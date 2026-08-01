import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import resend

from app.config import settings


def _build_reset_otp_content(otp: str) -> tuple[str, str]:
    text = f"""\
Your LC Connect password reset code is:

    {otp}

This code expires in 15 minutes.
If you did not request a password reset, ignore this email.
"""
    html = f"""\
<html>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;color:#1F2937">
  <div style="margin-bottom:24px">
    <span style="font-size:22px;font-weight:800;color:#4F8FC2">LC</span>
    <span style="font-size:22px;font-weight:800;color:#111827"> Connect</span>
  </div>
  <p style="margin-bottom:16px">Hi there,</p>
  <p style="margin-bottom:24px">
    We received a request to reset your password. Enter the code below in the app:
  </p>
  <div style="font-size:40px;font-weight:700;letter-spacing:10px;
              padding:20px 24px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {otp}
  </div>
  <p style="font-size:13px;color:#6B7280;margin-bottom:8px">
    This code expires in <strong>15 minutes</strong>.
  </p>
  <p style="font-size:13px;color:#6B7280">
    If you didn't request a password reset, you can safely ignore this email.
    Your password will not be changed.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    return text, html


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
    print(f'[EMAIL] To: {to_email} | Subject: {subject}\n{text}')


def _active_provider() -> str:
    p = settings.email_provider.lower()
    if p != 'auto':
        return p
    if settings.resend_api_key:
        return 'resend'
    if settings.smtp_username and settings.smtp_password:
        return 'smtp'
    return 'console'


def _send_email(to_email: str, subject: str, text: str, html: str) -> None:
    provider = _active_provider()
    if provider == 'resend':
        _send_via_resend(to_email, subject, text, html)
    elif provider == 'smtp':
        _send_via_smtp(to_email, subject, text, html)
    else:
        _send_via_console(to_email, subject, text, html)


# ── Public API ─────────────────────────────────────────────────────

def send_reset_otp(to_email: str, otp: str) -> None:
    text, html = _build_reset_otp_content(otp)
    _send_email(
        to_email=to_email,
        subject='Your LC Connect password reset code',
        text=text,
        html=html,
    )


def send_verification_otp(to_email: str, otp: str) -> None:
    text = f"""\
Your LC Connect email verification code is:

    {otp}

This code expires in 15 minutes.
If you did not create an account, ignore this email.
"""
    html = f"""\
<html>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:32px 24px;color:#1F2937">
  <div style="margin-bottom:24px">
    <span style="font-size:22px;font-weight:800;color:#4F8FC2">LC</span>
    <span style="font-size:22px;font-weight:800;color:#111827"> Connect</span>
  </div>
  <p style="margin-bottom:16px">Welcome to LC Connect!</p>
  <p style="margin-bottom:24px">
    Verify your email address with the code below:
  </p>
  <div style="font-size:40px;font-weight:700;letter-spacing:10px;
              padding:20px 24px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {otp}
  </div>
  <p style="font-size:13px;color:#6B7280;margin-bottom:8px">
    This code expires in <strong>15 minutes</strong>.
  </p>
  <p style="font-size:13px;color:#6B7280">
    If you didn't create an account, you can safely ignore this email.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    _send_email(
        to_email=to_email,
        subject='Verify your LC Connect email',
        text=text,
        html=html,
    )


def _build_invite_content(action_link: str, code: str, context: str) -> tuple[str, str]:
    if context == 'employer':
        heading = "You've been approved as an LC Connect employer partner"
        intro = "Your organization's Blueprint Bond application has been approved."
    else:
        heading = "You've been invited to LC Connect as an admin"
        intro = "You've been invited to help manage the LC Connect platform."

    text = f"""\
{heading}

{intro} Click the link below to accept your invite and set your password:

{action_link}

If the link doesn't open properly, enter this code on the invite page instead:

    {code}

This invite expires shortly. If you weren't expecting this, ignore this email.
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
  <p style="text-align:center;margin-bottom:24px">
    <a href="{action_link}"
       style="display:inline-block;padding:14px 28px;background:#4F8FC2;color:#fff;
              text-decoration:none;border-radius:10px;font-weight:700">
      Accept invite
    </a>
  </p>
  <p style="font-size:13px;color:#6B7280;margin-bottom:8px">
    If the button doesn't work, enter this code on the invite page instead:
  </p>
  <div style="font-size:28px;font-weight:700;letter-spacing:6px;
              padding:16px 20px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {code}
  </div>
  <p style="font-size:13px;color:#6B7280">
    This invite expires shortly. If you weren't expecting this, you can safely ignore this email.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    return text, html


def send_invite_email(to_email: str, *, action_link: str, code: str, context: str = 'admin') -> None:
    """The only invite email LC Connect ever sends — Supabase's own mailer/templates are bypassed
    entirely (see `app/shared/supabase_admin.invite_auth_user`, which calls
    `admin.generate_link` instead of `admin.invite_user_by_email` for exactly this reason: full
    control over branding and content, while Supabase still owns the actual auth token/identity).
    `context` is 'admin' or 'employer' — the only two things that ever invite through this path."""
    text, html = _build_invite_content(action_link, code, context)
    subject = (
        "You've been approved — LC Connect employer partner"
        if context == 'employer'
        else "You've been invited to LC Connect"
    )
    _send_email(to_email=to_email, subject=subject, text=text, html=html)


def _build_password_reset_content(action_link: str, code: str) -> tuple[str, str]:
    text = f"""\
Reset your LC Connect password

We received a request to reset your password. Click the link below:

{action_link}

If the link doesn't open properly, enter this code on the reset page instead:

    {code}

This link/code expires shortly. If you didn't request this, you can safely ignore this email —
your password will not be changed.
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
  <p style="text-align:center;margin-bottom:24px">
    <a href="{action_link}"
       style="display:inline-block;padding:14px 28px;background:#4F8FC2;color:#fff;
              text-decoration:none;border-radius:10px;font-weight:700">
      Reset password
    </a>
  </p>
  <p style="font-size:13px;color:#6B7280;margin-bottom:8px">
    If the button doesn't work, enter this code on the reset page instead:
  </p>
  <div style="font-size:28px;font-weight:700;letter-spacing:6px;
              padding:16px 20px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {code}
  </div>
  <p style="font-size:13px;color:#6B7280">
    This link/code expires shortly. If you didn't request this, you can safely ignore this
    email — your password will not be changed.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    return text, html


def send_password_reset_email(to_email: str, *, action_link: str, code: str) -> None:
    """Same bypass-Supabase's-own-mailer pattern as `send_invite_email` — see
    `app/shared/supabase_admin.request_password_reset`, which calls `admin.generate_link` (type
    'recovery') and hands the link/code here rather than letting Supabase email it directly."""
    text, html = _build_password_reset_content(action_link, code)
    _send_email(to_email=to_email, subject='Reset your LC Connect password', text=text, html=html)


def _build_signup_confirmation_content(action_link: str, code: str) -> tuple[str, str]:
    text = f"""\
Confirm your LC Connect account

Welcome to LC Connect! Click the link below to confirm your email address:

{action_link}

If the link doesn't open properly, enter this code in the app instead:

    {code}

This code expires shortly. If you didn't create this account, you can safely ignore this email.
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
  <p style="text-align:center;margin-bottom:24px">
    <a href="{action_link}"
       style="display:inline-block;padding:14px 28px;background:#4F8FC2;color:#fff;
              text-decoration:none;border-radius:10px;font-weight:700">
      Confirm my email
    </a>
  </p>
  <p style="font-size:13px;color:#6B7280;margin-bottom:8px">
    If the button doesn't work, enter this code in the app instead:
  </p>
  <div style="font-size:28px;font-weight:700;letter-spacing:6px;
              padding:16px 20px;background:#F0F7FF;border-radius:12px;
              text-align:center;color:#111827;margin-bottom:24px">
    {code}
  </div>
  <p style="font-size:13px;color:#6B7280">
    This code expires shortly. If you didn't create this account, you can safely ignore this
    email.
  </p>
  <hr style="border:none;border-top:1px solid #E5EAF0;margin:32px 0">
  <p style="font-size:12px;color:#9CA3AF">
    LC Connect &mdash; Livingstone College Campus Connection App
  </p>
</body>
</html>
"""
    return text, html


def send_signup_confirmation_email(to_email: str, *, action_link: str, code: str) -> None:
    """Covers the mobile app's direct `supabase.auth.signUp()`/`resend()` calls, which never touch
    this backend — see `app/features/auth/email_hook.py` (the Supabase 'Send Email' Auth Hook),
    which is what actually invokes this for those flows."""
    text, html = _build_signup_confirmation_content(action_link, code)
    _send_email(to_email=to_email, subject='Confirm your LC Connect account', text=text, html=html)
