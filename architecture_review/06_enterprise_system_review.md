# 06 — Enterprise System Review

**Date:** 2026-08-23  
**Scope:** Full-stack LC Connect (`backend/`, `mobile/`, admin portals)  
**Method:** Code review, architecture docs, CI/test posture, cross-layer flow analysis  
**Standard:** Enterprise expectations (SOC2-style controls, OWASP, SRE, WCAG) — not startup MVP norms

This document consolidates findings from backend engineering, security analysis, mobile UX, and system architecture review. Use it as the single reference for launch readiness, gaps, and prioritized next steps.

---

## 1. Executive Summary

LC Connect is a **feature-rich campus MVP** that has completed most of its planned auth and realtime migration. The codebase shows deliberate engineering: feature-first layout, OpenAPI snapshot guards, persist-before-publish messaging, Supabase Auth with admin MFA, and a mature chat client.

It is **not yet enterprise-grade for campus-wide production**. Primary blockers: horizontal scaling (no Redis fan-out), observability gaps, incomplete privacy/compliance controls, CI that skips DB integration tests, and mobile accessibility/offline maturity.

### Overall scores

| Dimension | Score | Enterprise bar |
|-----------|------:|----------------|
| Product completeness | 7.5/10 | Broad surface: discovery, chat, groups, campus hub, safety, admin |
| Backend architecture | 7.0/10 | Clean feature slices; single-instance ceiling |
| Security posture | 6.5/10 | Strong auth/authz patterns; distributed controls missing |
| Mobile UX | 6.0/10 | Cohesive design; accessibility and error consistency weak |
| Reliability / SRE | 5.5/10 | Message durability good; health/metrics/tracing absent |
| Compliance readiness | 4.5/10 | No export, incomplete audit, retention undefined |
| Test / CI confidence | 5.5/10 | ~350 tests exist; CI runs DB-free subset only |
| **Campus-wide launch readiness** | **5.8/10** | Pilot-ready single instance; not multi-instance production |

### Verdict

| Deployment mode | Recommendation |
|-----------------|----------------|
| **Controlled pilot** (hundreds of users, one API instance, manual monitoring) | Acceptable |
| **Campus-wide production** (2k+ students, autoscaling, compliance audit) | Blocked until P0 items complete |

---

## 2. End-to-End Flow Analysis

### 2.1 Authentication and onboarding

```text
Register (@livingstone.edu)
  → Supabase Auth
  → Email verified?
      No  → /verify-email
      Yes → POST /auth/bootstrap
            → Profile complete?
                No  → Onboarding (3 steps, student or staff)
                Yes → /home (Campus Hub)
```

**Strengths**

- Server-side gates: JWT → `auth_user_id` → app user → role/verification checks (`backend/app/dependencies.py`)
- Router redirect matrix handles pending email, unverified, incomplete profile (`mobile/lib/core/router/app_router.dart`)
- Campus domain allowlist enforced at bootstrap

**Gaps**

| Issue | Location | Impact |
|-------|----------|--------|
| Bootstrap failure silently signs user out | `mobile/lib/features/auth/providers/auth_provider.dart` | User sees login with no explanation |
| Onboarding has no draft persistence | `mobile/lib/features/onboarding/` | Mid-flow exit loses all input |

**Resolved (Sprint A)**

| Item | Resolution |
|------|------------|
| Register raw `error.toString()` | Uses `authErrorMessage()` (#12) |
| Misnamed `require_verified_student` | Renamed to `require_email_confirmed_user` (#13) |

---

### 2.2 Discovery → connection → chat

```text
Discovery cards
  → Connect → Connection request
  → Accept → Match + DM conversation
  → WebSocket subscribe + REST message sync
  → Live delivery
```

**Strengths**

- Block checks on connect, profile view, and message send
- Idempotent sends via `client_message_id` + DB unique constraint
- Optimistic UI with retry on failed bubbles
- Block/suspend triggers live WS revocation (`revoke_pair_access`, `disconnect_user`)

**Gaps**

| Issue | Location | Impact |
|-------|----------|--------|
| Connection requests only via Notifications | **Resolved (#11)** — Connect tab badge + header requests button |
| No pull-to-refresh on Discovery or Connections | Multiple screens | Harder recovery on stale data |

**Resolved (Sprint A)**

| Item | Resolution |
|------|------------|
| Discovery tune icon (false affordance) | Removed (#10); filters remain as chips |
| Chat initial history load failure silent | `AppErrorState` + retry (#4) |

---

### 2.3 Realtime messaging

**Strengths**

- Auth-first WebSocket protocol with typed Pydantic frames
- Persist-before-publish; keyset pagination + `/sync` on reconnect
- Bounded outbox (256 server / 50 client); slow consumers dropped
- Foreground in-app banners + unread badge lifecycle

**Limitations**

| Issue | Impact | Severity |
|-------|--------|----------|
| Single-process only (`InMemoryEventBus`; Redis configured but not implemented) | Cannot scale horizontally | **Resolved in code (#2)** — set `REDIS_URL` before multi-instance |
| WS token verified once at connect; mid-session expiry not enforced | Stale token on long-lived socket | High |
| `reap_idle()` / `ws_max_frame_bytes` unwired | **Resolved (#6)** — lifespan reaper + bounded receive | — |

---

### 2.4 Safety and moderation

**Strengths**

- Report/block sheets from discovery, DMs, group messages
- Message body snapshotted at report time for evidence
- Admin routes require Supabase MFA (`require_admin_aal2`)
- Suspension disconnects all live sockets

**Gaps**

| Issue | Impact |
|-------|--------|
| Report list views not audit-logged | Read access to PII/evidence unrecorded |
| Suspension reason returned in API but not persisted in audit log | **Resolved (#8)** — stored on `user.suspend` audit `after_data` |
| No appeal/reactivation product flow | Incomplete moderation lifecycle |
| Account deletion requires email string match only | **Resolved (#5)** — password step-up via Supabase GoTrue | — |

---

## 3. Backend Engineering Findings

### 3.1 Strengths

| Area | Evidence |
|------|----------|
| Feature-first architecture | 15+ domains under `backend/app/features/`, thin routers, fat services |
| API contract stability | OpenAPI snapshot + 142-route inventory in CI |
| Domain modeling | Unified `Conversation` (dm / group / staff_dm), normalized match pairs, per-member read boundaries |
| Message reliability | Idempotency index, persist-before-publish, cursor sync |
| Code hygiene | 600-line hard cap enforced; ruff + line limits in CI |
| Graceful degradation | WS shutdown on deploy; side effects wrapped so primary actions never fail |

### 3.2 Limitations

| Issue | Impact | Severity |
|-------|--------|----------|
| In-memory rate limits + WS manager | Abuse bypass and inconsistent revocation across instances | Critical at scale |
| Shallow `/health` (no DB/Redis check) | **Resolved (#3)** — `/health` liveness + `/health/ready` with DB probe (Redis seam) | — |
| No request correlation IDs | Slow incident debugging | High → **Resolved (Sprint B #7)** |
| No metrics/tracing/Sentry | Blind to latency, error rates, WS connection counts | High (WS count now on admin; latency/Sentry still open) |
| CI skips `tests/db/` (~40 files) | **Resolved (#1)** — `backend-db` CI job runs Postgres 16 integration suite | — |
| Legacy DB columns (`password_hash`, OTP) | Migration debt; low active risk while NULL | Medium |
| `admin/router.py` at 514 lines | Approaching maintainability threshold | Low |

**Key file:** `backend/app/main.py` — `/health` returns OK even if PostgreSQL is down. Admin `system-status` performs live checks but is gated behind admin auth.

---

## 4. Security Findings

### 4.1 Control maturity matrix

| Control | Status | Enterprise gap |
|---------|--------|----------------|
| Authentication (Supabase + JWKS) | Strong | Step-up on account deletion (#5) |
| Authorization / IDOR prevention | Strong | `require_email_confirmed_user` + `require_verified_connect_student` |
| WebSocket auth + per-action authz | Good (single instance) | Token expiry mid-session; idle/frame limits unwired |
| Rate limiting | Per-process only | Must be Redis-backed before scaling |
| Input validation | Pydantic + length bounds | Chunked upload bypass on body size middleware |
| File upload (avatars) | Decode, pixel cap, EXIF strip, re-encode | Document uploads lack AV scan |
| Audit logging | Stronger | Report views/resolutions + suspension reasons audited (#8) |
| Privacy rights | Partial | Export yes (#9); deletion yes; retention policy still incomplete |
| Encryption | TLS + DB at-rest | Messages plaintext at rest (by design for moderation) |
| Secrets management | Env-only service keys | No CI secret scanning |
| Production hardening | Stronger | `/docs` off in prod; security headers + HSTS in prod (#14) |

### 4.2 Critical findings (before multi-instance production)

1. **Distributed controls break at 2+ workers** — rate limits, WS state, and block revocation are process-local (`backend/app/shared/rate_limit.py`, `backend/app/features/realtime/manager.py`).
2. **Account deletion without reauthentication** — stolen bearer token can irreversibly anonymize account (`backend/app/features/account/router.py`, `service.py`).
3. **WS idle timeout and max frame size configured but not enforced** — `reap_idle()` unused; `ws_max_frame_bytes` not checked in gateway.

### 4.3 High-severity findings

| # | Finding | Key paths |
|---|---------|-----------|
| 1 | WS token expiry not handled mid-session | `backend/app/features/realtime/gateway.py`, `mobile/lib/core/realtime/realtime_client.dart` |
| 2 | No user data export (GDPR/CCPA) | **Resolved (#9)** — `GET /account/export` |
| 3 | Moderator report access not audit-logged | **Resolved (#8)** — `GET /admin/reports/{id}` → `report.view` |
| 4 | Suspension reason not persisted in audit trail | **Resolved (#8)** — required `reason` on suspend → audit |
| 5 | OpenAPI `/docs` enabled in production | **Resolved (Sprint B #14)** — disabled when `is_production` |
| 6 | Request body size limit bypass via chunked uploads | `backend/app/shared/request_limits.py` |
| 7 | Group hard-delete destroys unreported evidence | `docs/security/audit_and_data_retention.md` |

### 4.4 What security does well

- Generic 401 messages to clients; detailed rejection logged server-side
- Profile privacy returns 404 (not 403) to prevent enumeration
- Email hook uses Standard Webhooks signature verification
- Push notifications omit message bodies
- Scholar résumés in private bucket with signed URLs and employer view audit
- Live access revocation on block/suspend via WebSocket

---

## 5. Mobile UX Findings

### 5.1 Enterprise UX metrics

| Metric | Score | Notes |
|--------|------:|-------|
| Visual consistency | 4/5 | `AppTheme`, DM Sans, shared `AppErrorState` / `AppEmptyState` |
| Feedback and loading | 3.5/5 | Spinners common; chat history load now has error + retry; no skeletons yet |
| Recoverability | 3.5/5 | Retry on most lists; no global offline banner; partial pull-to-refresh |
| Accessibility | 1.5/5 | Zero `Semantics` widgets; minimal tooltips; 10px nav labels |
| Trust and safety UX | 4/5 | Clear report/block flows; staff identity in DMs |
| Navigation clarity | 3/5 | Connections buried; tab switch resets nested routes |
| Performance perception | 2.5/5 | No skeleton loaders; discovery lacks pagination cues |

### 5.2 Awkward UI patterns

| Pattern | Location | Status |
|---------|----------|--------|
| Dead filter button (tune icon) | Discovery search row | **Done** — removed (#10) |
| Dead attachment "+" button | Chat input | **Done** — removed (#10) |
| Raw errors in SnackBars | Register, connections, activities | **Done** — mapped via `apiErrorMessage` / `authErrorMessage` (#12) |
| Send spinner never activates | `chat_screen.dart` `_InputBar.sending` | Open |
| Orphaned `home_screen.dart` | Not in router | Open (#24) |
| Light mode only | No `darkTheme` | Open |
| Tab `context.go()` resets stack | `nav_shell.dart` | Open |

### 5.3 Chat UX (strongest mobile area)

**Strengths:** Optimistic send, reconnect sync, typing indicators, read receipts, connection banner, in-app foreground banners, failed-message retry, history-load error + retry (#4).

**Gaps:** Scroll-to-bottom when scrolled up; outbox-full warning; no media attachments.

### 5.4 Offline handling

| Mechanism | Status |
|-----------|--------|
| WS outbox for sends while disconnected | Implemented |
| WS suspend/resume on app background | Implemented |
| Friendly timeout messages (`apiErrorMessage`) | Implemented |
| Global connectivity/backend status banner | Wired (`backendStatusProvider` + `OfflineBannerHost`) |
| REST offline queue (connect, report, profile save) | Not implemented |
| Local cache for thread list / messages | Not implemented |

---

## 6. System Limitations and Architectural Debt

### 6.1 Migration progress vs. docs

`00_current_state_review.md` is a **historical** pre-WebSocket snapshot (bannered). Live status:
`PHASE_0_1_STATUS.md`. **Live checklist:** `todo_auth_websocket_security.md`.

| Roadmap phase | Status |
|---------------|--------|
| Phase 1 — Supabase Auth | Complete (legacy router removed) |
| Phase 2–4 — WebSocket + authz + idempotency | Complete (single instance) |
| Phase 5 — Redis fan-out | Code complete (`RedisEventBus` + `aallow`); provision `REDIS_URL` in deploy |
| Phase 6 — Push notifications | FCM integrated |
| Phase 7 — Privacy/export | Deletion + export (`GET /account/export`) |
| Phase 8 — Moderation audit | Partial |
| Phase 9 — Full CI test suite | Complete for backend unit + DB integration (Redis/multi-instance still open) |

### 6.2 Scaling ceiling

| Load profile | Current capacity | Blocker |
|--------------|------------------|---------|
| ~100–500 concurrent users, 1 Render instance | Supported | — |
| 2+ API instances / workers | Broken realtime + rate limits | Redis Pub/Sub |
| Campus-wide (~2k+ students active) | Risky | Single instance + no observability |
| Horizontal autoscaling | Not possible | In-memory WS manager |

### 6.3 Enterprise readiness scorecard

```text
Authentication & identity     ████████░░  8/10
Authorization & IDOR          ████████░░  8/10
Realtime messaging (1 node)   ███████░░░  7/10
Realtime messaging (scale)    ██░░░░░░░░  2/10
Data durability               ████████░░  8/10
Observability                 ██░░░░░░░░  2/10
Privacy & compliance          ████░░░░░░  4/10
Mobile UX (core flows)        ██████░░░░  6/10
Mobile accessibility          ██░░░░░░░░  2/10
CI / test confidence          █████░░░░░  5/10
Operational runbooks          ████░░░░░░  4/10
Documentation accuracy        █████░░░░░  5/10
```

---

## 7. Recommended Next Steps

Prioritized by ROI and launch risk. Each item includes owner hint, effort estimate, and acceptance criteria.

### Completed (Sprint A — 2026-08)

| # | Action | Completed | Notes |
|---|--------|-----------|-------|
| ✅ 4 | Fix silent chat load failure — error state + retry | 2026-08-23 | `chat_screen.dart` `_loadError` + `AppErrorState`; tests cover empty load path |
| ✅ 10 | Remove dead UI affordances (discovery tune, chat `+`) | 2026-08-24 | Widget tests assert icons stay absent |
| ✅ 12 | Standardize error messages (`apiErrorMessage` / `authErrorMessage`) | 2026-08-23 | Register, connections, activities, onboarding, discovery |
| ✅ 13 | Rename `require_verified_student` → `require_email_confirmed_user` | 2026-08-24 | All routers + auth-guard tests (staff pass / student-only gate) |
| ✅ 1 | Add PostgreSQL to CI — run `backend/tests/db/` on every PR | 2026-08-24 | Separate `backend-db` job (Postgres 16); `REQUIRE_TEST_DB=1` hard-fails if DB missing; unit job uses `--ignore=tests/db` |

### Completed (Sprint B — ✅ complete)

| # | Action | Completed | Notes |
|---|--------|-----------|-------|
| ✅ 3 | Deep health `/health/ready` with DB (+ Redis seam) | 2026-08-24 | Liveness `/health` unchanged; readiness returns 503 when DB down; Redis skipped until configured; shared probe reused by admin system-status |
| ✅ 6 | Wire WS idle reaper + enforce `ws_max_frame_bytes` | 2026-08-24 | Lifespan runs `run_idle_reaper`; gateway uses bounded receive (`ws_io.py`); close code 4409; tests for reap + oversize |
| ✅ 5 | Step-up auth for account deletion | 2026-08-25 | `password` required; verified via Supabase GoTrue; 403 on wrong password (not 401); rate-limited; mobile password field |
| ✅ 7 | Request correlation IDs + basic WS metric | 2026-08-25 | `X-Request-ID` middleware + log `[req=…]`; stamped on audit `after_data`; admin `websocket_connections` count (per-instance). Send latency / error counters deferred |
| ✅ 14 | Disable `/docs` in prod + security headers | 2026-08-25 | `docs`/`redoc`/`openapi.json` null when `is_production`; `SecurityHeadersMiddleware` (CSP, XFO, nosniff, Referrer-Policy); HSTS only in prod |

### Completed (Sprint C — ✅ complete)

| # | Action | Completed | Notes |
|---|--------|-----------|-------|
| ✅ 2 | Redis EventBus + distributed rate limits | 2026-08-25 | `REDIS_URL` → async client, `RedisEventBus` Pub/Sub fan-out, control events (suspend/block/announce); `RateLimiter.aallow` Lua token bucket; memory fallback when unset/outage. Typing TTL / cross-instance presence deferred |
| ✅ 8 | Audit report views/resolutions; persist suspension reasons | 2026-08-26 | `reason` required on suspend → audit `after_data`; `GET /admin/reports/{id}` audits `report.view`; `POST .../resolve` audits `report.resolve`; admin Moderation/Users UI wired |
| ✅ 9 | Data export endpoint | 2026-08-26 | `GET /account/export` JSON (`schema_version: 1`); audited `account.export`; 5/day rate limit; mobile Profile → Download my data (clipboard) |
| ✅ 15 | Refresh stale architecture/security docs | 2026-08-26 | `PHASE_0_1_STATUS.md` rewritten; security overview/RLS/rate-limit/audit; docs README + folder_structure; Realtime messaging marked historical |

### Completed (Sprint D — in progress)

| # | Action | Completed | Notes |
|---|--------|-----------|-------|
| ✅ 11 | Surface connection requests on Connect tab | 2026-08-26 | Nav badge on Connect; header `ConnectionRequestsButton` → `/connections`; `incomingConnectionCountProvider`; WS refresh on `connection_request` |

### P0 — Before campus-wide launch (remaining blockers)

| # | Action | Owner | Effort | Acceptance criteria |
|---|--------|-------|--------|---------------------|
| — | Provision Redis in each deploy env + set `REDIS_URL` before multi-instance | Ops | — | Health `/health/ready` redis=ok; 2+ API instances share fan-out |

### P1 — Enterprise hardening (30–60 days)

| # | Action | Owner | Effort | Acceptance criteria |
|---|--------|-------|--------|---------------------|
| ~~7~~ | ~~Add request correlation IDs + basic metrics (WS connections, send latency, errors)~~ | Backend / SRE | — | ✅ Done (Sprint B): `X-Request-ID` + logs + admin WS count; latency/error metrics still open |
| ~~8~~ | ~~Audit report views/resolutions; persist suspension reasons~~ | Backend | — | ✅ Done (Sprint C): `report.view` / `report.resolve` / suspend `reason` on audit |
| ~~9~~ | ~~Data export endpoint (`GET /account/export` or async job)~~ | Backend | — | ✅ Done (Sprint C): sync JSON export + audit + mobile download |
| ~~11~~ | ~~Surface connection requests from Connect tab with badge~~ | Mobile | — | ✅ Done (Sprint D): nav badge + Connect header CTA |
| ~~14~~ | ~~Disable `/docs` in production; add security headers middleware~~ | Backend | — | ✅ Done (Sprint B): docs off in prod; security headers + HSTS |
| ~~15~~ | ~~Refresh stale docs (`PHASE_0_1_STATUS.md`, `docs/security/overview.md`)~~ | Docs | — | ✅ Done (Sprint C): docs match Supabase Auth + FastAPI WS + Redis seam |

### P2 — UX and compliance maturity (60–90 days)

| # | Action | Owner | Effort | Acceptance criteria |
|---|--------|-------|--------|---------------------|
| 16 | Accessibility pass: `Semantics`, tooltips, 48dp touch targets, text scaling | Mobile | 2 weeks | VoiceOver/TalkBack navigable on core flows |
| 17 | Skeleton loaders on hub + list screens | Mobile | 3–5 days | Primary lists show placeholder content while loading |
| 18 | ~~Global offline/connectivity banner (wire `backendStatusProvider` or connectivity listener)~~ | Mobile | 2–3 days | ~~User sees banner when server unreachable~~ ✅ |
| 19 | Pull-to-refresh on Discovery, Activities, Connections, Profile | Mobile | 2 days | All primary list screens support manual refresh |
| 20 | Retire legacy DB columns after backfill runbook | Backend / DBA | 1 week | `password_hash`, OTP columns dropped; migration applied |
| 21 | Retention purge automation for soft-deleted messages | Backend | 1 week | Scheduled job per published retention policy |
| 22 | Suspension appeal / support workflow | Product + Backend | 2 weeks | User-facing appeal path documented and implemented |
| 23 | Chat maturity: scroll-to-bottom FAB, outbox-full warning, optional local cache | Mobile | 1–2 weeks | Long offline sessions don't silently drop sends |
| 24 | Delete or archive orphaned `home_screen.dart` | Mobile | 0.5 day | No unrouted dead screens in codebase |
| 25 | Formal existing-user linking runbook / backfill script | Backend / Ops | 3–5 days | All historical users have `auth_user_id` populated |

---

## 8. Implementation Order (Suggested Sprint Plan)

Aligns with `05_execution_roadmap.md` and closes gaps identified in this review.

### Sprint A — Confidence and correctness (2 weeks) — ✅ complete

1. ~~Chat load error UI (#4)~~ ✅
2. ~~Error message standardization (#12)~~ ✅
3. ~~Remove dead UI affordances (#10)~~ ✅
4. ~~Rename `require_verified_student` → `require_email_confirmed_user` (#13)~~ ✅
5. ~~PostgreSQL in CI (#1)~~ ✅

**Next:** Sprint B — Production hardening (#3 deep health, #6 WS idle/frame limits, #5 step-up deletion, …)

### Sprint B — Production hardening (2–3 weeks)

1. ~~Deep health endpoint (#3)~~ ✅
2. ~~WS idle reaper + frame size enforcement (#6)~~ ✅
3. ~~Step-up auth for deletion (#5)~~ ✅
4. ~~Correlation IDs (#7)~~ ✅
5. ~~Disable `/docs` in prod + security headers (#14)~~ ✅

**Sprint B complete.** Sprint C #2 (Redis EventBus + distributed rate limits) implemented in code — provision `REDIS_URL` before running 2+ API instances.

### Sprint C — Scale and compliance (3–4 weeks)

1. ~~Redis EventBus + distributed rate limits (#2)~~ ✅ (code; ops must set `REDIS_URL`)
2. ~~Audit completeness (#8)~~ ✅
3. ~~Data export (#9)~~ ✅
4. ~~Documentation refresh (#15)~~ ✅

**Sprint C complete** (code + docs). Remaining ops: provision Redis before multi-instance. Next: Sprint D — UX / accessibility.

### Sprint D — UX and accessibility (3–4 weeks)

1. ~~Connection requests discoverability (#11)~~ ✅
2. ~~Global offline banner (#18)~~ ✅
3. Pull-to-refresh (#19) ← next
4. Accessibility pass (#16)
5. Skeleton loaders (#17)

---

## 9. Key File Reference

| Area | Primary paths |
|------|---------------|
| App entry | `backend/app/main.py` |
| Health probes | `backend/app/shared/health.py` (`/health`, `/health/ready`) |
| Auth dependencies | `backend/app/dependencies.py` |
| JWT verification | `backend/app/security/supabase_jwt.py` |
| Models | `backend/app/models/*.py` |
| WS gateway | `backend/app/features/realtime/gateway.py` |
| WS manager | `backend/app/features/realtime/manager.py` |
| Event bus (Redis seam) | `backend/app/features/realtime/event_bus.py` |
| Messages service | `backend/app/features/messages/service.py` |
| Safety / blocks | `backend/app/features/safety/service.py` |
| Rate limits | `backend/app/shared/rate_limit.py` |
| Account deletion | `backend/app/features/account/` |
| Mobile router | `mobile/lib/core/router/app_router.dart` |
| Mobile realtime | `mobile/lib/core/realtime/realtime_client.dart` |
| Chat screen | `mobile/lib/features/messages/screens/chat_screen.dart` |
| Shared UI states | `mobile/lib/shared/widgets/app_states.dart` |
| CI pipeline | `.github/workflows/ci.yml` |
| Live checklist | `architecture_review/todo_auth_websocket_security.md` |

---

## 10. Related Documents

| Document | Purpose |
|----------|---------|
| `00_current_state_review.md` | Original risk inventory (partially stale) |
| `01_target_architecture.md` | Target system shape |
| `04_security_privacy_compliance.md` | Security and privacy requirements |
| `05_execution_roadmap.md` | Phased implementation plan |
| `todo_auth_websocket_security.md` | Live implementation checklist |
| `DECISION_LOG.md` | Accepted architecture decisions |

**This document (`06_enterprise_system_review.md`) is the consolidated launch-readiness reference.** Update it when P0/P1 items are completed or when scores change materially.
