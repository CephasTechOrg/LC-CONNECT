# Foundation Status (Phases 0–5+)

**Updated:** 2026-08-30  
**Canonical architecture:** [`README.md`](./README.md) · [`01_target_architecture.md`](./01_target_architecture.md) · [`06_enterprise_system_review.md`](./06_enterprise_system_review.md)

This file replaces the July 2026 Phase 0–1 snapshot. It describes **what is live now**, not the
migration WIP of that era.

---

## Working end-to-end today

```text
Flutter (iOS / Android)
  → Supabase Auth          signup / login / email confirm / session / MFA (admin)
  → FastAPI                JWT verify (JWKS) → users.auth_user_id → app user id
       → PostgreSQL        source of truth (messages, matches, profiles, …)
       → WebSocket         wss://…/api/v1/ws  (persist-before-publish)
       → Redis (optional)  Pub/Sub fan-out + distributed rate limits when REDIS_URL set
       → FCM / APNs        offline push (generic copy; no message bodies)
```

**Locked decisions (do not regress):**

| Concern | Choice |
|---------|--------|
| Auth | Supabase Auth only — no custom password/OTP product path |
| Authorization | FastAPI only (REST + WebSocket) |
| Chat realtime | FastAPI WebSockets + Redis Pub/Sub — **not** Supabase Realtime |
| Message history | PostgreSQL only — Redis is never history |
| Identity | `token.sub` → `users.auth_user_id` → `users.id` |

---

## Phase checklist (current)

| Phase | Status |
|-------|--------|
| **0 — Baseline** | ✅ Docs, Alembic, CI (unit + Postgres), line limits, pinned deps |
| **1 — Supabase Auth** | ✅ JWT verify, bootstrap, Flutter Auth, email-confirmed / student gates, Dio refresh |
| **2–4 — WebSocket messaging** | ✅ Auth-first WS, persist-before-publish, idempotent sends, sync/cursor, typing, idle/frame limits |
| **5 — Redis** | ✅ Code (`RedisEventBus`, `RateLimiter.aallow`); **ops deferred** — provision `REDIS_URL` later, right before multi-instance |
| **6 — Push** | ✅ FCM path when credentials configured |
| **7 — Privacy** | ✅ Account deletion + `GET /account/export`; soft-delete message purge (cron + script, 90-day default); suspension appeals (#22) |
| **Hardening (Sprint A–C)** | ✅ See [`06_enterprise_system_review.md`](./06_enterprise_system_review.md) |

Live checklist: [`todo_auth_websocket_security.md`](./todo_auth_websocket_security.md).

---

## What was retired

- Custom FastAPI password / OTP session auth as the product path (legacy router removed).
- Supabase Realtime as the chat delivery plane (Flutter uses the FastAPI WS client).
- Misnamed `require_verified_student` → `require_email_confirmed_user` (staff can pass email-confirmed gates; social matching stays student-only).

**Still deferred (not blockers for single-instance pilot):**

- Drop unused legacy DB columns (`password_hash`, OTP fields) after a formal backfill/runbook (#20).
- Redis typing/presence TTL keys (client timers work today).
- Soft-archive for group hard-delete.
- ~~Retention purge job for soft-deleted messages~~ ✅ (`scripts/purge_soft_deleted_messages.py` + daily cron).

---

## Ops notes

| Item | Guidance |
|------|----------|
| Single API instance | Fine without Redis — **current plan**; Redis deferred until workers |
| 2+ workers / instances | Set `REDIS_URL` on every instance **first**, then scale |
| Health | `GET /health` liveness · `GET /health/ready` (DB required; Redis when configured) |
| Message retention cron | [`MESSAGE_RETENTION_CRON_RUNBOOK.md`](./MESSAGE_RETENTION_CRON_RUNBOOK.md) — daily purge of soft-deleted messages (**create once on Render/GitHub Actions**) |
| Suspension appeals | [`SUSPENSION_APPEAL_RUNBOOK.md`](./SUSPENSION_APPEAL_RUNBOOK.md) — `SUPPORT_EMAIL` on API; migration auto on deploy |
| Production launch | [`PRODUCTION_SETUP_CHECKLIST.md`](./PRODUCTION_SETUP_CHECKLIST.md) — master env + smoke-test gate |
| Prod OpenAPI | `/docs` disabled when `ENVIRONMENT=production` |

---

## Historical note

The original 2026-07-21 Phase 0–1 write-up (branch `feat/supabase-auth-phase1`, “do not start WebSockets yet”) is **obsolete**. Prefer this file and `architecture_review/` over older `docs/architecture/realtime-messaging.md` or `docs/product/todo.md` when they conflict.
