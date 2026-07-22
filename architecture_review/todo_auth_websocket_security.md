# LC Connect — Auth, WebSocket, Redis, and Security Checklist

## Foundation (Phase 0)

- [x] Migration branch (`feat/supabase-auth-phase1`)
- [x] Local DB created (`lc_connect_db`) + tables seeded
- [x] Alembic baseline / head stamped (`a1b2c3d4e5f6`)
- [x] Secret scan and `.gitignore` (`.env` ignored)
- [x] Contributor setup docs (`docs/local_dev_setup.md`)
- [x] Daily start docs (`docs/daily_dev_start.md`)
- [x] Cursor rules (architecture + file structure)
- [x] Dependency lock — direct deps pinned to exact versions in `requirements.txt` + `requirements-dev.txt` (reproducible across CI, Render, local; Render/CI install these directly)
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
- [x] Password recovery functional — OTP-code flow (`resetPasswordForEmail` → `verifyOTP(recovery)` → `updateUser`); no deep link required
- [ ] (Optional) Recovery **deep links** — tap-email-to-open-app UX. Deferred: needs iOS `Info.plist` URL scheme + `passwordRecovery` auth-event routing + **Supabase dashboard redirect-URL allow-list** (external). Not needed for the feature to work.
- [ ] Formal existing-user linking runbook / backfill script
- [ ] Retire custom auth (`AUTH_LEGACY_ENABLED=false`)
- [ ] Drop old credential columns (`password_hash`, OTP fields)
- [ ] Rotate old custom JWT secret
- [~] Auth automated tests — done: verified/unverified, active/suspended, admin-aal2 (all cases), missing-token 401, and route-wiring (unverified → 403 on all student GET routes) in `tests/test_auth_guards.py`. Still open: bootstrap concurrency + real expired/invalid token cases.

## Phase 2 — Slice 1 (backend gateway) — DONE

Single-instance, in-memory `ConnectionManager` behind an `EventBus` seam (Redis-ready).
Backend `app/features/realtime/` + `messages` REST paging/sync + idempotency. 25 realtime
tests (protocol, rate-limit, manager backpressure/revocation, gateway lifecycle over TestClient).
Deferred to later slices: Redis fan-out, push (FCM/APNs), presence, Flutter client, app-level
idle reaper + graceful-shutdown lifespan (uvicorn ping/pong covers dead-socket detection now).

## WebSocket (Phase 2+)

- [x] `/api/v1/ws`
- [x] Auth-first protocol
- [x] Stable schemas/errors (typed discriminated-union frames + error codes)
- [x] Auth timeout (idle reaper + close-on-idle deferred; uvicorn ping/pong detects dead sockets)
- [x] Payload limits (frame size + body length)
- [x] Malformed-event limits (bounded, then close)
- [ ] Graceful shutdown lifespan (manager.shutdown wired, lifespan not yet mounted)
- [ ] Metrics without content/tokens
- [ ] Flutter connection-state provider (next slice)
- [ ] Reconnect/backoff/jitter (next slice)
- [ ] Restore subscriptions (next slice)
- [ ] Clear on logout (next slice)

## Authorization — DONE (Slice 1)

- [x] Subscribe/unsubscribe
- [x] Match membership
- [x] Active/verified state
- [x] Block check
- [x] Subscription limits
- [x] Reauthorize sends (re-queried per send — catches mid-session block/suspend)
- [x] Revoke on block (safety.add_block → manager.revoke_pair)
- [x] Revoke on suspension (admin.suspend_user → manager.close_user)

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

## Messages — DONE (Slice 1, except Flutter retry UI)

- [x] `client_message_id`
- [x] Unique sender/client constraint (partial-unique index)
- [x] Idempotent insert (shared by REST + WS)
- [x] Persist before publish
- [x] `message.ack`
- [x] `message.created`
- [x] Cursor pagination (keyset `GET /threads/{id}?before_created_at&before_id&limit`)
- [x] Reconnect sync (`GET /threads/{id}/sync?after_created_at&after_id`)
- [x] Read/unread support (`messages.read` → `messages.receipt`)
- [x] Message length limit (URL-specific limits: later)
- [ ] Retry UI (Flutter, next slice)

## Typing/presence

- [x] `typing.start`
- [x] `typing.stop`
- [x] Throttle (token bucket per user+conversation)
- [ ] 3–4 second expiry (client-side via active:false now; Redis TTL later)
- [x] Ignore self (excluded from broadcast)
- [x] Never persist typing
- [ ] Presence privacy setting if enabled (deferred)

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
