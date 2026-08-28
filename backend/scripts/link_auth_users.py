"""Link historical LC Connect users to Supabase Auth (`users.auth_user_id`).

Dry-run (default):
  cd backend && .venv/bin/python scripts/link_auth_users.py

Apply links for emails that already exist in Supabase Auth:
  .venv/bin/python scripts/link_auth_users.py --apply

Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (same as the API).
Full procedure: architecture_review/AUTH_USER_LINKING_RUNBOOK.md
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

# Allow `python scripts/link_auth_users.py` from backend/ without PYTHONPATH.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import AsyncSessionLocal
from app.shared.auth_linking import link_existing_auth_users
from app.shared.supabase_admin import get_auth_user_id_by_email


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        '--apply',
        action='store_true',
        help='Write auth_user_id for matched emails (default is dry-run)',
    )
    return p.parse_args(argv)


async def _run(*, apply: bool) -> int:
    async with AsyncSessionLocal() as db:
        report = await link_existing_auth_users(
            db,
            lookup_auth_id=get_auth_user_id_by_email,
            apply=apply,
        )

    mode = 'APPLY' if apply else 'DRY-RUN'
    print(f'=== Auth user linking ({mode}) ===')
    print(f'Already linked:           {report.already_linked}')
    print(f'Deleted/tombstone (NULL): {report.deleted_unlinked}  (OK — stay unlinked)')
    print(f'Would link / linked:      {len(report.linked)}')
    for u in report.linked:
        print(f'  + {u.email}  ({u.id})')
    print(f'Missing in Supabase:      {len(report.missing_in_supabase)}')
    for u in report.missing_in_supabase:
        print(f'  ? {u.email}  ({u.id}) — user must sign up (bootstrap) or be invited')
    print(f'Conflicts:                {len(report.conflicts)}')
    for u, reason in report.conflicts:
        print(f'  ! {u.email}: {reason}')

    if report.ok_for_credential_drop:
        print('\nGate OK: every live account has (or would have) auth_user_id.')
        return 0

    print('\nGate NOT OK: resolve missing/conflicts (sign-up/invite), then re-run.')
    return 1


def main(argv: list[str] | None = None) -> None:
    args = _parse_args(argv)
    code = asyncio.run(_run(apply=args.apply))
    sys.exit(code)


if __name__ == '__main__':
    main()
