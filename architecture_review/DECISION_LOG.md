# Architecture Decision Log

## ADR-001 — Supabase Auth

**Decision:** Use Supabase Auth for credentials, sessions, recovery, confirmation, and MFA. FastAPI remains the application authorization authority.

## ADR-002 — FastAPI WebSockets

**Decision:** Replace Supabase Realtime chat with FastAPI WebSockets.

**Reason:** It removes custom JWT-to-Realtime coupling, centralizes match/block/suspension enforcement, supports consistent local PostgreSQL development, provides clearer debugging, and enables immediate live revocation.

## ADR-003 — Redis

**Decision:** Use Redis Pub/Sub for cross-instance fan-out and TTL keys for typing/presence.

**Limitation:** Pub/Sub is at-most-once and not durable. PostgreSQL remains the source of truth.

## ADR-004 — Persist before publish

**Decision:** Commit the message to PostgreSQL before publishing a live event.

## ADR-005 — REST synchronization

**Decision:** Recover missed events through cursor-based REST history after reconnect.

## ADR-006 — Offline delivery

**Decision:** Use FCM/APNs when the mobile app is backgrounded or terminated.

## ADR-007 — Supabase Realtime removal

**Decision:** Remove Supabase Realtime from messaging after the FastAPI WebSocket path is complete and tested. Supabase Auth, PostgreSQL, and Storage remain.
