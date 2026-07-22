# LC Connect — Auth, WebSocket, Redis, and Security Checklist

## Foundation (Phase 0)

- [x] Migration branch (`feat/supabase-auth-phase1`)
- [x] Local DB created (`lc_connect_db`) + tables seeded
- [x] Alembic baseline / head stamped (`a1b2c3d4e5f6`)
- [x] Secret scan and `.gitignore` (`.env` ignored)
- [x] Contributor setup docs (`docs/local_dev_setup.md`)
- [x] Daily start docs (`docs/daily_dev_start.md`)
- [x] Cursor rules (architecture + file structure)
- [ ] Dependency lock strategy (`requirements.lock` / pinned CI)
- [x] CI pipeline (`.github/workflows/ci.yml` — line limits + backend snapshot tests + `flutter analyze`)
- [x] Backend regression harness (`backend/tests/` — OpenAPI snapshot, route inventory, import smoke)
- [x] File-length enforcement (`scripts/check_line_limits.py`, 600 hard cap; pre-push hook + CI)

## Supabase Auth (Phase 1)

- [x] `users.auth_user_id` column
- [x] Unique partial index `uq_users_auth_user_id`
- [x] Local configuration working (Flutter + FastAPI + local Postgres + cloud Supabase Auth)
- [x] Email confirmation path (Supabase confirm + app verify OTP screen)
- [x] Livingstone domain restriction (server-side; Gmail allow-list **dev only**)
- [x] Remove production Gmail exceptions (prod path domains-only)
- [x] FastAPI JWT verification (HS256 via `SUPABASE_JWT_SECRET` + JWKS path for RS/ES)
- [x] Validate issuer / audience / expiry / subject / algorithm / role
- [x] Idempotent `POST /api/v1/auth/bootstrap` (feature folder)
- [x] Flutter Auth migration (signup / login / verify / reset via Supabase)
- [x] Dio uses current Supabase access token
- [x] `require_verified_student` dependency **exists**
- [x] Admin `require_admin_aal2` wired on admin routes
- [x] Apply `require_verified_student` to student-protected REST routes (profiles, discovery, connections, messages, activities, safety — all endpoints; unverified users get 403)
- [x] Token refresh behavior — Dio interceptor recovers a 401 by refreshing the session once and replaying the request (shared in-flight refresh); `AuthNotifier` listens to `onAuthStateChange` to keep the stored token fresh and sign out on session death. (Reconnect/backoff is Phase 2 WebSocket work.)
- [ ] Recovery deep links (iOS URL scheme / universal links) fully configured
- [ ] Formal existing-user linking runbook / backfill script
- [ ] Retire custom auth (`AUTH_LEGACY_ENABLED=false`)
- [ ] Drop old credential columns (`password_hash`, OTP fields)
- [ ] Rotate old custom JWT secret
- [~] Auth automated tests — done: verified/unverified, active/suspended, admin-aal2 (all cases), missing-token 401, and route-wiring (unverified → 403 on all student GET routes) in `tests/test_auth_guards.py`. Still open: bootstrap concurrency + real expired/invalid token cases.

## WebSocket (Phase 2+)

- [ ] `/api/v1/ws`
- [ ] Auth-first protocol
- [ ] Stable schemas/errors
- [ ] Heartbeat and timeout
- [ ] Payload limits
- [ ] Malformed-event limits
- [ ] Graceful shutdown
- [ ] Metrics without content/tokens
- [ ] Flutter connection-state provider
- [ ] Reconnect/backoff/jitter
- [ ] Restore subscriptions
- [ ] Clear on logout

## Authorization

- [ ] Subscribe/unsubscribe
- [ ] Match membership
- [ ] Active/verified state
- [ ] Block check
- [ ] Subscription limits
- [ ] Reauthorize sends
- [ ] Revoke on block
- [ ] Revoke on suspension

## Redis

- [ ] Provision service
- [ ] Async client
- [ ] Environment prefixes
- [ ] Pub/Sub publisher/subscriber
- [ ] Deliver to local sockets
- [ ] Typing TTL
- [ ] Optional presence TTL
- [ ] Distributed rate limits
- [ ] Outage behavior
- [ ] Health metrics

## Messages

- [ ] `client_message_id`
- [ ] Unique sender/client constraint
- [ ] Idempotent insert
- [ ] Persist before publish
- [ ] `message.ack`
- [ ] `message.created`
- [ ] Cursor pagination
- [ ] Reconnect sync
- [ ] Read/unread support
- [ ] Message and URL limits
- [ ] Retry UI

## Typing/presence

- [ ] `typing.start`
- [ ] `typing.stop`
- [ ] Throttle
- [ ] 3–4 second expiry
- [ ] Ignore self
- [ ] Never persist typing
- [ ] Presence privacy setting if enabled

## Notifications

- [ ] FCM/APNs
- [ ] Device-token table
- [ ] Token refresh/revocation
- [ ] Send after commit
- [ ] Generic preview default
- [ ] Conversation deep link
- [ ] Foreground/background/terminated handling

## Privacy/safety

- [ ] Centralized profile visibility
- [ ] Block enforcement on profile reads
- [ ] Verified-only enforcement
- [ ] Block/history policy
- [ ] Message reporting
- [ ] Report limits/workflow
- [ ] Admin audit log
- [ ] Suspension reason
- [ ] Appeal/reactivation
- [ ] Export/deletion
- [ ] Retention policy
- [ ] Published policies

## Avatar security

- [ ] Signature validation
- [ ] Safe decode and pixel cap
- [ ] EXIF removal
- [ ] Re-encode
- [ ] Generated object names
- [ ] Private bucket/signed URLs evaluation
- [ ] Avatar deletion/report

## Tests

- [ ] Supabase token tests
- [ ] Bootstrap concurrency
- [x] Verified/suspended tests (`tests/test_auth_guards.py`)
- [ ] WebSocket auth tests
- [ ] Subscription authorization
- [ ] Active-chat block revocation
- [ ] Idempotent sends
- [ ] Cursor sync
- [ ] Multi-instance Redis
- [ ] Redis outage
- [ ] Background/reconnect
- [ ] Rate limits
- [ ] Upload attacks
- [ ] Admin MFA/audit
