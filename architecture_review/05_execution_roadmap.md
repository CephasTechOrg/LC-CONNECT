# 05 — Execution Roadmap

## Phase 0 — Baseline

- Create a migration branch and database backup.
- Establish Alembic/Supabase migration baseline.
- Inventory secrets and verify `.gitignore`.
- Pin dependencies and add CI.
- Pause major new chat/social features.

## Phase 1 — Supabase Auth

- Add `users.auth_user_id`.
- Configure local/staging Auth and confirmation.
- Enforce Livingstone domains.
- Implement JWKS verification.
- Add idempotent bootstrap.
- Update Flutter Auth and Dio.
- Add recovery deep links.
- Require verified users and admin `aal2`.
- Link current test users.
- Retire custom auth after a rollback period.

## Phase 2 — WebSocket foundation

- Add `/api/v1/ws`.
- Add protocol schemas and stable errors.
- Require authentication first.
- Build a one-process connection manager.
- Add heartbeat and graceful shutdown.
- Add Flutter WebSocket provider.
- Add reconnect/backoff and subscription restoration.

## Phase 3 — Conversation authorization

- Add subscribe/unsubscribe events.
- Check match membership, block status, active state, and verification.
- Bound subscriptions.
- Revoke active access on block/suspension.

## Phase 4 — Message reliability

- Add `client_message_id` and unique constraint.
- Persist before broadcasting.
- Add acknowledgement and canonical live event.
- Add cursor history and reconnect synchronization.
- Add read/unread state and rate limits.

## Phase 5 — Redis

- Provision Redis.
- Add async client, Pub/Sub publisher, and subscriber task.
- Prefix channels by environment.
- Deliver events to local sockets.
- Add typing/presence TTLs and distributed limits.
- Define degraded behavior and health metrics.

## Phase 6 — Push notifications

- Add device-token storage.
- Register/revoke FCM/APNs tokens.
- Notify only after committed messages.
- Use generic notification text.
- Deep-link to conversations.

## Phase 7 — Privacy/uploads

- Centralize profile visibility.
- Enforce block and verified-only settings.
- Harden avatar validation and delivery.
- Add avatar deletion, account export, and account deletion.

## Phase 8 — Moderation/audit

- Add report-message support and rate limits.
- Add admin audit table.
- Persist suspension reasons.
- Add appeals/reactivation and incident runbook.

## Phase 9 — Tests

Backend, WebSocket, Flutter, Redis, migration, authorization, concurrency, retry, upload, and admin security tests must run in CI.

## Immediate sprint

1. Migration baseline.
2. `auth_user_id`.
3. Supabase JWT verifier.
4. Bootstrap endpoint.
5. Flutter Supabase Auth.
6. WebSocket authentication.
7. Connection manager.
8. Conversation subscription authorization.
9. Idempotent message send/ack.
10. Cursor synchronization.
11. Redis bridge.
12. Security tests.

Do not add media chat, group chat, precise location, or dating expansion during this sprint.
