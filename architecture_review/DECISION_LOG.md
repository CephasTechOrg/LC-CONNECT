# Architecture Decision Log

## ADR-001 — Supabase Auth

**Decision:** Use Supabase Auth for credentials, sessions, recovery, confirmation, and MFA. FastAPI remains the application authorization authority.

## ADR-002 — FastAPI WebSockets

**Decision:** Replace Supabase Realtime chat with FastAPI WebSockets.

**Reason:** It removes custom JWT-to-Realtime coupling, centralizes match/block/suspension enforcement, supports consistent local PostgreSQL development, provides clearer debugging, and enables immediate live revocation.

## ADR-003 — Redis

**Decision:** Use Redis Pub/Sub for cross-instance fan-out and TTL keys for typing/presence.

**Limitation:** Pub/Sub is at-most-once and not durable. PostgreSQL remains the source of truth.

**Ops (2026-08-27):** Do **not** provision Redis until ready to run 2+ API workers/instances. Single-instance memory fallback is intentional until then; add Redis (+ `REDIS_URL`) in the same window as scaling, Redis first.

## ADR-004 — Persist before publish

**Decision:** Commit the message to PostgreSQL before publishing a live event.

## ADR-005 — REST synchronization

**Decision:** Recover missed events through cursor-based REST history after reconnect.

## ADR-006 — Offline delivery

**Decision:** Use FCM/APNs when the mobile app is backgrounded or terminated.

## ADR-007 — Supabase Realtime removal

**Decision:** Remove Supabase Realtime from messaging after the FastAPI WebSocket path is complete and tested. Supabase Auth, PostgreSQL, and Storage remain.

## ADR-008 — Dual-email signup & campus verification

**Decision:** Keep the **campus email** as the Supabase auth identity (`users.email`, login). Collect a **personal contact email** at signup; route signup/recovery OTP delivery to `contact_email` via the Send Email hook and `user_metadata.contact_email`. Introduce a separate **`campus_verified`** admin flag for the profile checkmark (Phase 2); do not use `is_verified` for the badge.

**Reason:** Student campus inboxes frequently block transactional mail; personal inboxes are reliable. OTP proves inbox control; admin verification proves community membership.

**Spec:** `docs/features/auth/DUAL_EMAIL_CAMPUS_VERIFICATION.md`
