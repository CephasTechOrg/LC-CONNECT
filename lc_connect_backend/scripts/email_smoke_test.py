"""
Smoke test for the email provider stack.

Usage:
    cd backend
    python scripts/email_smoke_test.py --to your@email.com
"""

import argparse
import sys
import os

# Allow running from the backend/ directory without installing the package.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config import settings
from app.email import _active_provider, send_reset_otp


def main() -> None:
    parser = argparse.ArgumentParser(description='LC Connect email smoke test')
    parser.add_argument('--to', required=True, help='Recipient email address')
    args = parser.parse_args()

    provider = _active_provider()
    print(f'Active email provider : {provider}')
    print(f'EMAIL_PROVIDER setting: {settings.email_provider}')

    if provider == 'resend':
        key_preview = (settings.resend_api_key or '')[:8] + '...'
        print(f'Resend API key        : {key_preview}')
        print(f'From                  : {settings.resend_from_email}')
    elif provider == 'smtp':
        print(f'SMTP host             : {settings.smtp_host}:{settings.smtp_port}')
        print(f'SMTP user             : {settings.smtp_username}')
        print(f'From                  : {settings.smtp_from}')
    else:
        print('No provider configured — email will be printed to console.')

    print(f'\nSending test reset OTP to: {args.to}')
    try:
        send_reset_otp(to_email=args.to, otp='123456')
        print('Done. Check your inbox (or console output above).')
    except Exception as exc:
        print(f'FAILED: {exc}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
