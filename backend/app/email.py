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
