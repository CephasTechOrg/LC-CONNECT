# Phase 0–1 Foundation Status

**Date:** 2026-07-21  
**Branch:** `feat/supabase-auth-phase1`  
**Verdict:** Phase 1 core auth path is **working locally**. Foundation is **strong enough to continue**, with a short hardening list before Phase 2 (WebSockets).

## Working end-to-end today

```text
iOS Simulator (Flutter)
  → Supabase Auth (cloud)     signup / login / email confirm / session
  → FastAPI localhost:8000    POST /auth/bootstrap, /auth/me, domain APIs
       → local Postgres       users.auth_user_id + profiles + app data
```

Verified:

- Backend health OK
- Alembic at `a1b2c3d4e5f6`
- `users.auth_user_id` present
- Unique partial index `uq_users_auth_user_id` present
- Feature layout: `app/features/auth/{router,service,schema}.py`
- Security helpers: `app/security/{supabase_jwt,legacy_jwt,passwords}.py`
- Flutter uses Supabase session token via Dio
- Contributor docs: `local_dev_setup.md`, `daily_dev_start.md`
- Cursor rules for architecture + file structure

## Phase checklist summary

| Phase | Status |
|-------|--------|
| **0 — Baseline** | Mostly done (docs, branch, local DB, Alembic). Missing: dependency lock + CI |
| **1 — Supabase Auth** | **Core done** (JWT verify, bootstrap, Flutter Auth). Open: wire verified-student on routes, deep links, retire legacy auth, tests |
| **2+ — WebSocket / Redis / messages** | Not started |

Full item checklist: [`todo_auth_websocket_security.md`](./todo_auth_websocket_security.md)

## Bugs fixed during local bring-up

1. Missing `asyncpg` / no venv → created `.venv` + installed requirements  
2. Postgres not running / missing `lc_connect_db` → started Postgres.app, created DB, seeded tables  
3. Broken “initial” Alembic migration on empty DB → create-all fallback for fresh installs  
4. Async `MissingGreenlet` on bootstrap profile access → explicit profile queries + reload  
5. Duplicate profile insert (`autoflush=False`) → flush before existence check  
6. Missing unique `auth_user_id` index after stamp → created `uq_users_auth_user_id`

## Remaining Phase 1 hardening (do before / early in Phase 2)

1. **Wire `require_verified_student`** on student REST routers (discovery, connections, messages, activities, etc.) — dependency exists but is not applied everywhere yet  
2. **Auth tests** for bootstrap, invalid/expired tokens, suspended users  
3. **Token refresh story** for long sessions (critical once WebSockets land)  
4. **Recovery deep links** for iOS if password reset should open the app  
5. Keep `AUTH_LEGACY_ENABLED=true` until mobile is fully on Supabase Auth in all environments, then retire custom auth columns  
6. Optional: CI + locked Python deps

## Do not start yet

- FastAPI WebSocket gateway  
- Redis Pub/Sub  
- Message `client_message_id` / cursor sync  
- FCM/APNs  

Those are Phase 2+.

## Recommended next move

Close the Phase 1 hardening items above (especially verified-student route guards + a few auth tests), then begin Phase 2 WebSocket foundation from `03_fastapi_websocket_messaging.md`.
