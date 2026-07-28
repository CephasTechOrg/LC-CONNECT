"""Promote an existing bootstrapped user to admin (Supabase Auth path).

Admin is never inferred from email. Flow:
  1. Create/sign up the user in Supabase Auth
  2. Call POST /auth/bootstrap once (mobile or admin login) so users row exists
  3. Run this script to set role=admin and write an audit log
  4. Enroll MFA (TOTP) — admin APIs require aal2

Usage:
  cd backend && source .venv/bin/activate
  python scripts/promote_admin.py you@livingstone.edu
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from uuid import UUID

# Allow `python scripts/promote_admin.py` from backend/ without PYTHONPATH.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select

from app.database import AsyncSessionLocal
from app.models import User
from app.shared.audit import record_audit
from app.shared.email_roles import normalize_campus_email


async def promote(email: str, *, actor_id: UUID | None) -> None:
    try:
        normalized = normalize_campus_email(email)
    except ValueError as exc:
        # Allow promoting an already-bootstrapped row even if domain policy is strict;
        # still prefer campus emails for admins.
        normalized = email.strip().lower()
        print(f'Warning: {exc}', file=sys.stderr)

    async with AsyncSessionLocal() as db:
        user = (await db.execute(select(User).where(User.email == normalized))).scalar_one_or_none()
        if user is None:
            raise SystemExit(
                f'No app user for {normalized}. Sign in once (bootstrap) before promoting.'
            )

        before = {'role': user.role, 'status': user.status, 'is_active': user.is_active}
        if user.role == 'admin':
            print(f'{normalized} is already admin (id={user.id}).')
            return

        user.role = 'admin'
        user.status = 'active'
        user.is_active = True
        user.is_verified = True

        await record_audit(
            db,
            actor_id=actor_id or user.id,
            action='user.promote_admin',
            target_type='user',
            target_id=user.id,
            before_data=before,
            after_data={'role': user.role, 'status': user.status, 'is_active': user.is_active},
        )
        await db.commit()
        print(f'Promoted {normalized} to admin (id={user.id}). Enroll MFA before using /admin APIs.')


def main() -> None:
    parser = argparse.ArgumentParser(description='Promote a bootstrapped user to admin')
    parser.add_argument('email', help='Email of an existing users row')
    parser.add_argument(
        '--actor-email',
        default=None,
        help='Optional existing admin email to record as audit actor (defaults to the promoted user)',
    )
    args = parser.parse_args()

    async def _run() -> None:
        actor_id = None
        if args.actor_email:
            async with AsyncSessionLocal() as db:
                actor = (
                    await db.execute(select(User).where(User.email == args.actor_email.strip().lower()))
                ).scalar_one_or_none()
                if actor is None or actor.role != 'admin':
                    raise SystemExit(' --actor-email must be an existing admin')
                actor_id = actor.id
        await promote(args.email, actor_id=actor_id)

    asyncio.run(_run())


if __name__ == '__main__':
    main()
