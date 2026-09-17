"""Deprecated shim — use `scripts/bootstrap_db.py`.

This script used to call `Base.metadata.create_all` unconditionally and then seed. That was wrong
in two ways once Alembic arrived: it never recorded the schema version, so a freshly created
database still looked un-migrated to Alembic; and it ran *after* `alembic upgrade head` in the
deploy command, which is backwards — the migration ran first and failed on an empty database
before this script ever got the chance to build anything.

It is kept because several docs still name it (`README.md`, `docs/getting-started/setup.md`,
`docs/product/todo.md`). Rather than leave those instructions doing the wrong thing, it now
delegates, so following an older doc still produces a correct database.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from bootstrap_db import main  # noqa: E402

if __name__ == '__main__':
    print('note: init_db.py is deprecated — use `python scripts/bootstrap_db.py`\n')
    raise SystemExit(main())
