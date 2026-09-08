"""Backfill link previews for campus posts that already have `external_url`.

Dry-run (default):
  cd backend && .venv/bin/python scripts/backfill_campus_post_link_previews.py

Apply unfurls:
  .venv/bin/python scripts/backfill_campus_post_link_previews.py --apply

Limit how many rows to process in one run:
  .venv/bin/python scripts/backfill_campus_post_link_previews.py --apply --limit 50
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import AsyncSessionLocal
from app.shared.link_preview_backfill import backfill_missing_link_previews


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument(
        '--apply',
        action='store_true',
        help='Fetch and persist previews (default is dry-run)',
    )
    p.add_argument(
        '--limit',
        type=int,
        default=100,
        help='Max posts to process in this run (default: 100)',
    )
    return p.parse_args(argv)


async def _run(*, apply: bool, limit: int) -> int:
    async with AsyncSessionLocal() as db:
        report = await backfill_missing_link_previews(db, apply=apply, limit=limit)

    mode = 'APPLY' if apply else 'DRY-RUN'
    print(f'=== Campus post link-preview backfill ({mode}) ===')
    print(f'Eligible (url set, preview unset): {report.eligible}')
    print(f'Processed:                         {report.processed}')
    print(f'  ok:                              {report.ok}')
    print(f'  failed:                          {report.failed}')
    if report.sample_ids:
        print('Sample post ids:')
        for pid in report.sample_ids:
            print(f'  - {pid}')
    if not apply and report.eligible:
        print('\nRe-run with --apply to unfurl eligible posts.')
    return 0


def main(argv: list[str] | None = None) -> None:
    args = _parse_args(argv)
    raise SystemExit(asyncio.run(_run(apply=args.apply, limit=args.limit)))


if __name__ == '__main__':
    main()
