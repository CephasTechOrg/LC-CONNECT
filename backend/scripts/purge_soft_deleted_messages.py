"""Purge soft-deleted messages past the retention window.

Dry-run (default):
  cd backend && .venv/bin/python scripts/purge_soft_deleted_messages.py

Apply deletions:
  .venv/bin/python scripts/purge_soft_deleted_messages.py --apply

Override retention window (days):
  .venv/bin/python scripts/purge_soft_deleted_messages.py --days 90 --apply

Full procedure: `architecture_review/MESSAGE_RETENTION_CRON_RUNBOOK.md`
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.config import settings
from app.database import AsyncSessionLocal
from app.shared.message_retention import purge_soft_deleted_messages


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        '--apply',
        action='store_true',
        help='Hard-delete eligible rows (default is dry-run)',
    )
    p.add_argument(
        '--days',
        type=int,
        default=None,
        help=f'Retention window in days (default: {settings.message_soft_delete_retention_days})',
    )
    p.add_argument(
        '--batch-size',
        type=int,
        default=500,
        help='Rows deleted per batch when applying (default: 500)',
    )
    return p.parse_args(argv)


async def _run(*, apply: bool, retention_days: int, batch_size: int) -> int:
    async with AsyncSessionLocal() as db:
        report = await purge_soft_deleted_messages(
            db,
            retention_days=retention_days,
            apply=apply,
            batch_size=batch_size,
        )

    mode = 'APPLY' if apply else 'DRY-RUN'
    print(f'=== Soft-deleted message purge ({mode}) ===')
    print(f'Retention window:  {report.retention_days} days')
    print(f'Cutoff (UTC):      {report.cutoff.isoformat()}')
    print(f'Eligible:          {report.eligible}')
    print(f'Purged:            {report.purged}')
    if report.sample_ids:
        print('Sample message ids (oldest eligible):')
        for mid in report.sample_ids:
            print(f'  - {mid}')
    if not apply and report.eligible:
        print('\nRe-run with --apply to delete eligible rows.')
    elif apply and report.purged:
        print('\nPurge complete. Report snapshots (`reports.message_body`) are unchanged.')
    return 0


def main(argv: list[str] | None = None) -> None:
    args = _parse_args(argv)
    retention_days = args.days if args.days is not None else settings.message_soft_delete_retention_days
    code = asyncio.run(_run(apply=args.apply, retention_days=retention_days, batch_size=args.batch_size))
    sys.exit(code)


if __name__ == '__main__':
    main()
