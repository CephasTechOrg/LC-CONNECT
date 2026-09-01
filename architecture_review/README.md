# LC Connect — Architecture, Authentication, Realtime, and Security Review

**Repository reviewed:** `CephasTechOrg/LC-CONNECT`  
**Revision:** Version 2 — FastAPI WebSocket architecture

## Final architecture decision

LC Connect should use:

- **Mobile application:** Flutter + Riverpod
- **Authentication and sessions:** Supabase Auth
- **API authorization and business logic:** FastAPI
- **Realtime messaging:** FastAPI WebSockets
- **Cross-instance realtime fan-out:** Redis Pub/Sub
- **Typing and presence:** Redis keys with short TTLs
- **Persistent application data:** PostgreSQL
- **Production database:** Supabase PostgreSQL
- **Profile images:** Supabase Storage
- **Offline notifications:** Firebase Cloud Messaging and APNs

Supabase Realtime is no longer part of the recommended chat architecture.

## Why the decision changed

The existing Supabase Realtime implementation depends on custom FastAPI JWTs, shared signing configuration, RLS, Realtime authorization, matching database environments, and Flutter channel state all working together. FastAPI WebSockets establish one security boundary: the same backend that verifies matches, blocks, suspension, rate limits, and message validity also controls live delivery.

## Documents

1. `00_current_state_review.md` — repository findings and current risks.
2. `01_target_architecture.md` — final architecture.
3. `02_supabase_auth_migration.md` — authentication migration.
4. `03_fastapi_websocket_messaging.md` — realtime protocol and design.
5. `04_security_privacy_compliance.md` — security, privacy, safety, and retention.
6. `05_execution_roadmap.md` — ordered implementation plan.
7. `06_enterprise_system_review.md` — **enterprise review: findings, scores, and prioritized next steps.**
8. `todo_auth_websocket_security.md` — implementation checklist.
9. `DECISION_LOG.md` — accepted architecture decisions.
10. `SOURCES.md` — primary references.
11. `AUTH_USER_LINKING_RUNBOOK.md` — existing-user `auth_user_id` backfill (#25).
12. `MESSAGE_RETENTION_CRON_RUNBOOK.md` — **daily cron setup** for soft-deleted message purge (#21).
13. `SUSPENSION_APPEAL_RUNBOOK.md` — suspend / appeal / reactivate workflow (#22).
14. `PRODUCTION_SETUP_CHECKLIST.md` — **master launch checklist** (env, cron, smoke tests).
15. `PHASE_0_1_STATUS.md` — live migration status.
16. `docs/features/auth/DUAL_EMAIL_CAMPUS_VERIFICATION.md` — dual-email signup + campus verification (ADR-008).

## Engineering conventions

Before implementing any phase, follow [`CONVENTIONS.md`](../CONVENTIONS.md) — the feature-first
structure and file-length rules the codebase now enforces. The backend has been sliced into
`app/features/<domain>/{router,service,schema}` with a `shared/` kernel, and mobile screens are
decomposed into `features/<feature>/widgets/`. See
[`docs/architecture/folder_structure.md`](../docs/architecture/folder_structure.md) for the full layout.

## Immediate implementation order

1. Establish migrations and backups.
2. Add Supabase Auth identity linking.
3. Verify Supabase tokens in FastAPI.
4. Build the authenticated WebSocket gateway.
5. Add conversation authorization.
6. Add idempotent messages and cursor synchronization.
7. Add Redis for multi-instance fan-out and rate limits.
8. Add FCM/APNs for background delivery.
9. Complete tests, moderation, audit logs, and privacy controls.

## Progress

See `PHASE_0_1_STATUS.md` (updated 2026-08-26 — current phase status) and the checked items in
`todo_auth_websocket_security.md`. For launch gaps and sprint order, use
`06_enterprise_system_review.md`.
