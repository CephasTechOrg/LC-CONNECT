import smtplib
import ssl
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.config import settings


def send_reset_otp(to_email: str, otp: str) -> None:
    if not settings.smtp_user or not settings.smtp_password:
        # No SMTP configured — print to console so dev can still test
        print(f'[DEV] Password reset OTP for {to_email}: {otp}')
        return

    msg = MIMEMultipart('alternative')
    msg['Subject'] = 'Your LC Connect password reset code'
    msg['From'] = settings.smtp_from
    msg['To'] = to_email

    text_body = f"""\
Your LC Connect password reset code is:

    {otp}

This code expires in 15 minutes.
If you did not request a password reset, ignore this email.
"""

    html_body = f"""\
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

    msg.attach(MIMEText(text_body, 'plain'))
    msg.attach(MIMEText(html_body, 'html'))

    context = ssl.create_default_context()
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
        server.ehlo()
        server.starttls(context=context)
        server.login(settings.smtp_user, settings.smtp_password)
        # Use smtp_user as envelope sender — required by Gmail
        server.sendmail(settings.smtp_user, to_email, msg.as_string())
