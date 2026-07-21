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
- [ ] CI pipeline

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
- [ ] Apply `require_verified_student` to student-protected REST routes (discovery, connections, messages, etc.)
- [ ] Token refresh / reconnect behavior (needed especially for WebSockets in Phase 2)
- [ ] Recovery deep links (iOS URL scheme / universal links) fully configured
- [ ] Formal existing-user linking runbook / backfill script
- [ ] Retire custom auth (`AUTH_LEGACY_ENABLED=false`)
- [ ] Drop old credential columns (`password_hash`, OTP fields)
- [ ] Rotate old custom JWT secret
- [ ] Auth automated tests (bootstrap concurrency, token cases)

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
- [ ] Verified/suspended tests
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
