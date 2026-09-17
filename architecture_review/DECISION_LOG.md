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

## ADR-009 — Presence is not a product feature

**Decision:** Do not derive or display online/offline presence. Messaging shows delivery and read
state; it does not show whether a person is currently online.

**Reason:** Beta report #22 warned against equating push reachability with presence. The backend
already avoids that — "offline" is derived from `manager.user_socket_count()` and device tokens are
consulted only *after* that decision, so presence gates push and never the reverse. Adding a
presence *feature* is the part that would be wrong: it needs cross-instance state (Redis, currently
deferred by ADR-003), it invites privacy objections on a campus social app, and it degrades badly on
mobile because the socket is torn down on background by design — a user with the app in their pocket
would read as "offline" while being perfectly reachable. An "Online" badge that is wrong half the
time is worse than none.

**If revisited:** derive from a throttled `users.last_active_at` written on WS auth and at most once
per heartbeat, present it as "Active recently" rather than a binary dot, and gate it behind an
explicit per-user privacy toggle defaulting to off. Never from device-token existence. Requires
Redis for cross-instance correctness, so strictly after the Redis/worker milestone.

## ADR-010 — Read receipts are unconditional in v1

**Decision:** Read receipts remain always-on, with no per-user opt-out, for the first release of the
delivery/read work (Phase 3).

**Reason:** Recorded so it reads as a choice rather than an oversight. An always-on "seen" signal on
a campus social app is a legitimate privacy objection, and the conventional remedy is a per-user
toggle with reciprocity — disable yours and you stop seeing others'. That is deliberately deferred:
it adds a settings surface, a user column, and a branch in the receipt path, for a concern no beta
tester has raised yet.

**If revisited:** the reciprocity rule is the important part. A toggle that hides your receipts while
still showing you everyone else's is the version users object to.

