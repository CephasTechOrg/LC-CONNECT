# LC Connect — Engineering Conventions

This is the single source of truth for how code is organized and sized in LC Connect.
It applies to both the FastAPI backend and the Flutter mobile app. Enforced in CI
(`.github/workflows/ci.yml`) via `scripts/check_line_limits.py`, `ruff`, and `flutter analyze`.

---

## 1. File-length rules

| Level | Lines | Enforcement |
|---|---:|---|
| ✅ Ideal | ≤ 300 | — |
| 🟡 Soft target | ≤ 400 | Warning (printed, non-blocking) |
| 🔴 Hard cap | ≤ 600 | **CI fails** |
| Functions/methods | ~50 | Guidance (not gated) |

The line count is a **proxy for single responsibility**, not a law. A file a little over the
cap is a prompt to split *or* justify — not automatically a defect. Genuine, reviewed
exceptions go in the `ALLOWLIST` in `scripts/check_line_limits.py` with a one-line reason.

Run locally before pushing:

```bash
python scripts/check_line_limits.py            # whole repo
python scripts/check_line_limits.py --warn-only
```

---

## 2. Feature-first (vertical slice) architecture

Organize by **feature**, layer **inside** each feature. Backend and mobile mirror each other so
a developer moving between them isn't surprised.

### Backend — `lc_connect_backend/app/`

```text
app/
  main.py                 # wires feature routers together
  config.py  database.py  dependencies.py  security/   # shared kernel (cross-cutting infra)
  models.py               # ALL SQLAlchemy models (one metadata — do not split)
  shared/                 # cross-feature helpers (serializers, policies, storage)
  features/
    <feature>/
      router.py           # thin — HTTP only (parse request, call service, return schema)
      service.py          # business rules live here
      schema.py           # Pydantic request/response models for this feature
      __init__.py         # exposes `router`
```

### Mobile — `lc_connect_mobile/lib/`

```text
lib/
  core/                   # api, router, theme, storage, constants (cross-cutting infra)
  shared/                 # widgets used by multiple features (e.g. nav_shell)
  features/
    <feature>/
      providers/          # Riverpod state + all data access (API calls live here)
      screens/            # thin — compose widgets, read providers
      widgets/            # extracted presentational sub-widgets
      data/               # (optional) models + repository when a feature grows
```

---

## 3. The rules that keep it clean

1. **Routers / screens stay thin.** No business logic or direct DB/HTTP calls in a router or a
   screen. Backend logic → `service.py`. Mobile data access → `providers/`.
2. **A feature owns its whole vertical slice** — router + service + schema (+ widgets on mobile).
   There is no shared `services.py` / `schemas.py` god-file.
3. **Dependencies point inward.** Features may import from `core`/`app` root and `shared`, but a
   feature must **never** import another feature's `service.py`/`providers`. Cross-feature needs
   go through `shared/`.
4. **Models stay centralized** (`app/models.py`) — one SQLAlchemy metadata, no circular imports.

### Backend shared-kernel ownership

| Helper | Home | Used by |
|---|---|---|
| `profile_to_public` | `app/shared/serializers.py` | profiles, connections, messages, discovery |
| `users_are_blocked` | `app/shared/policies.py` | connections, messages, safety |
| `SupabaseStorageService` / `storage_service` | `app/shared/storage.py` | profiles |
| `calculate_match` | `features/discovery/service.py` | discovery only |

---

## 4. Regression safety net (backend)

The API contract is snapshotted so internal refactors provably change no behavior:

- `tests/test_openapi_snapshot.py` — full `app.openapi()` vs committed `tests/baseline/openapi.json`.
- `tests/test_route_inventory.py` — the `(METHOD, PATH)` set vs `tests/baseline/routes.txt`.
- `tests/test_import_smoke.py` — every `app.*` module imports cleanly.

Run: `pytest`  (no live database needed — these inspect the assembled app only).

When the API is *intentionally* changed, regenerate the baseline:

```bash
UPDATE_SNAPSHOTS=1 pytest tests/test_openapi_snapshot.py tests/test_route_inventory.py
```

If a snapshot fails during a pure refactor, **stop** — a move altered behavior.
