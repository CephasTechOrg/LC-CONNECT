# CLAUDE.md — LC Connect

Guidance for AI agents and developers working in this repo. **Read [`CONVENTIONS.md`](CONVENTIONS.md)
in full before writing code** — this file is the quick reference.

## Project

Campus social/matching app for Livingstone College. Two apps:
- `backend/` — FastAPI + async SQLAlchemy + PostgreSQL (Supabase), migrating auth to Supabase Auth.
- `mobile/` — Flutter + Riverpod + supabase_flutter.

Layout: [`docs/architecture/folder_structure.md`](docs/architecture/folder_structure.md).
Architecture direction: `architecture_review/`.

## File-length rules (enforced in CI)

| Size | Meaning |
|---|---|
| ≤ 300 | ideal |
| ≤ 400 | soft target — a warning over this, but CI still passes |
| **> 600** | **hard cap — CI fails** |

Check anytime: `python scripts/check_line_limits.py` (covers `.py` and `.dart`). Enforced by CI and by
a pre-push hook — enable it once per clone with `git config core.hooksPath .githooks`.
The count is a proxy for single-responsibility — if you exceed it, split the file (see the widget /
service patterns below) or add a reviewed entry to `ALLOWLIST` in the script.

## Code craft (guidance, not enforced)

Beyond the enforced rules, aim for healthy code — see [`CODE_STYLE.md`](CODE_STYLE.md). In short:
one job per function, short and shallow (guard clauses over deep nesting), few parameters, pure logic
with I/O at the edges, names that state intent, comments that explain *why*. These are judgment calls,
not gates — clarity for the next reader wins.

## Structure: feature-first (vertical slice)

- **Backend:** `app/features/<domain>/{router,service,schema}.py`. Routers stay thin; business logic
  in `service.py`. Cross-feature helpers/DTOs live in `app/shared/` — a feature must NEVER import
  another feature's `service.py`. Models are centralized in `app/models.py` (one metadata).
  - Legacy island: `app/routers/auth.py` + `app/schemas.py` (transitional password auth only — do
    not extend; slated for deletion).
- **Mobile:** `lib/features/<feature>/{providers,screens,widgets}`. Screens stay thin; extract big
  sub-widgets into `widgets/` using Dart `part`/`part of` files. Data access lives in `providers/`,
  never in screens.

## Before you finish — verify

Run **`/verify`** (defined in `.claude/commands/`) to execute the whole gate at once, or run the
pieces manually:

```bash
# Backend (from backend/):
.venv/bin/pytest --ignore=tests/db   # unit + API snapshot (no Postgres)
.venv/bin/pytest tests/db            # integration (needs local Postgres / TEST_DATABASE_URL)
.venv/bin/ruff check .

# Mobile (from mobile/):
flutter analyze

# Repo:
python scripts/check_line_limits.py
```

CI runs both backend suites: unit/snapshot without Postgres, and `tests/db` against a
Postgres 16 service with `REQUIRE_TEST_DB=1` (missing DB fails the job — never silent skip).

**The backend API contract is snapshot-guarded.** A pure refactor must leave `pytest` green
(byte-identical OpenAPI). Only regenerate the baseline for intentional API changes:
`UPDATE_SNAPSHOTS=1 .venv/bin/pytest`. Details: [`CONVENTIONS.md`](CONVENTIONS.md) §4.
