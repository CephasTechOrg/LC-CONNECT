# LC Connect — Folder Structure

This document describes the actual folder structure. The project follows a **feature-first
(vertical slice)** architecture on both the backend and mobile. The rules that govern it
(file-length limits, feature ownership, dependency direction) live in
[`CONVENTIONS.md`](../../CONVENTIONS.md) at the repo root — read that first.

```text
lc-connect/
  mobile/   # Flutter app
  backend/  # FastAPI backend
  supabase/            # Supabase SQL migrations (RLS, publications)
  docs/     # Project documentation
  scripts/             # repo tooling (check_line_limits.py)
  CONVENTIONS.md       # engineering conventions (structure + line rules)
  .github/workflows/   # CI (line limits, backend tests/lint, flutter analyze)
  README.md
  .gitignore
```

## 1. Feature-first principle

Both apps are organized **by feature**, and layered **inside** each feature. A developer
moving between backend and mobile sees the same shape. Cross-cutting infrastructure lives in a
shared kernel (`core`/`shared` on mobile, root modules + `shared/` on the backend); features
depend on the kernel, never sideways on each other.

## 2. Mobile App (`mobile/`)

Technology: **Flutter + Dart + Riverpod + supabase_flutter**

```text
lib/
  main.dart                          # entry point — Supabase.initialize, ProviderScope
  core/                              # cross-cutting infrastructure
    api/          api_client.dart, health_provider.dart
    constants/    app_constants.dart
    router/       app_router.dart     # GoRouter + auth guards
    storage/      secure_storage.dart
    theme/        app_theme.dart
    widgets/      avatar_widget.dart
  features/
    <feature>/
      providers/   # Riverpod state + ALL data access (API calls live here)
      screens/     # thin — compose widgets, read providers
      widgets/     # extracted presentational sub-widgets
  shared/
    widgets/      nav_shell.dart      # bottom navigation used across features
```

Features: `auth`, `onboarding`, `home`, `discovery`, `connections`, `messages`, `activities`,
`profile`, `safety`.

### Screens stay thin — `widgets/` holds the pieces

Large screens are decomposed so no file exceeds the 600-line cap (target 400). Sub-widgets are
extracted into `features/<feature>/widgets/` using Dart **`part` files**: the screen declares
`part '../widgets/<name>.dart';` and each widget file starts with
`part of '../screens/<screen>.dart';`. This keeps the sub-widgets private to the screen library
and lets them share the screen's imports and helpers, while each file stays small. Example —
`home/`:

```text
home/
  screens/home_screen.dart           # state + wiring only (~190 lines)
  widgets/
    home_header.dart                 # part of home_screen.dart
    home_feed_sections.dart
    home_student_card.dart
    home_activity_list.dart
    home_match_cards.dart
```

## 3. Backend (`backend/`)

Technology: **FastAPI + PostgreSQL (Supabase) + async SQLAlchemy + Alembic**

```text
app/
  main.py               # FastAPI app, CORS, includes every feature router
  config.py             # pydantic-settings from .env
  database.py           # async engine + session (get_db)
  dependencies.py       # auth dependencies: get_current_user, require_verified_student,
                        #   require_admin, require_admin_aal2, get_supabase_claims
  security/             # supabase_jwt (JWKS verify), legacy_jwt, passwords
  models.py             # ALL SQLAlchemy models (one metadata — intentionally centralized)
  email.py  seed.py     # infra
  shared/               # cross-feature kernel
    schemas.py          # shared DTOs: ProfilePublic, ReportRead
    serializers.py      # profile_to_public
    policies.py         # users_are_blocked
    profiles.py         # get_profile_by_user_id, profile_load_options
    storage.py          # SupabaseStorageService / storage_service
  features/
    <feature>/
      router.py         # thin — HTTP only
      service.py        # business rules (omit when the feature has none, e.g. lookups)
      schema.py         # Pydantic request/response models for this feature
      __init__.py       # exposes `router`
  routers/              # LEGACY — transitional auth only (see §5)
    auth.py
  schemas.py            # LEGACY — auth DTOs only (see §5)
alembic/                # migrations
pyproject.toml          # ruff + pytest config
requirements.txt        # runtime deps
requirements-dev.txt    # + pytest, pytest-asyncio, ruff (CI/dev only)
tests/                  # regression safety net (see §6)
```

Features: `auth`, `profiles`, `discovery`, `connections`, `messages`, `activities`, `safety`,
`admin`, `lookups`.

### Ownership rules

- **Routers stay thin.** Business logic lives in `service.py`, not the router.
- **A feature owns its slice** (router + service + schema). There is no shared `services.py`.
- **Dependencies point inward.** A feature may import from root modules (`config`, `database`,
  `dependencies`, `models`, `security`) and from `shared/`, but **never** from another feature's
  `service.py`. Genuinely cross-feature helpers/DTOs live in `shared/` (that is why
  `ProfilePublic`, `ReportRead`, `profile_to_public`, and `users_are_blocked` are there).
- **Models stay centralized** in `models.py` — one SQLAlchemy metadata avoids circular imports.

## 4. Supabase (`supabase/`)

```text
supabase/migrations/    # versioned SQL Alembic does not manage (RLS policies, publications)
```

Run in Supabase Dashboard → SQL Editor or via `supabase db push`. See
`security_rls_messages.md`.

## 5. Legacy auth island — **removed**

The transitional `app/routers/auth.py` + `app/schemas.py` password/OTP island has been **deleted**.
Auth lives only in `app/features/auth/`. Unused DB columns (`password_hash`, OTP fields) may still
exist as nullable leftovers — do not write to them; dropping them is a separate DBA runbook
(`architecture_review/06_enterprise_system_review.md` item #20).

## 6. Regression safety net (`backend/tests/`)

No live database needed — these inspect the assembled app only:

- `test_openapi_snapshot.py` — full `app.openapi()` vs committed `tests/baseline/openapi.json`.
- `test_route_inventory.py` — the `(METHOD, PATH)` set vs `tests/baseline/routes.txt`.
- `test_import_smoke.py` — every `app.*` module imports.

Run `pytest`. Regenerate the baseline only for intentional API changes with
`UPDATE_SNAPSHOTS=1 pytest`.

## 7. Docs (`docs/`)

```text
project_description.md  architecture.md  folder_structure.md (this file)
database.md  realtime-messaging.md  security_rls_messages.md
local_dev_setup.md  daily_dev_start.md  deployment.md  ...
```
