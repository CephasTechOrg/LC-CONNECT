# Security & Authorization — Overview

How LC Connect keeps user data safe: **who you are** (authentication), **what you can reach**
(authorization), and **how data is protected** (encryption). Written to be understood, not just
skimmed — a reviewer or a new developer should be able to trust the model after reading this.

**Architecture source of truth:** [`architecture_review/`](../../architecture_review/README.md)
(Supabase Auth + FastAPI authorization + FastAPI WebSockets). Prefer that folder when older notes
conflict.

Companion docs: [`rls_messages.md`](./rls_messages.md) (database-level RLS defense-in-depth),
[`rate_limiting.md`](./rate_limiting.md) (abuse limits),
[`audit_and_data_retention.md`](./audit_and_data_retention.md) (deletion, export & evidence).

---

## 1. Authentication — who you are

Login runs on **Supabase Auth**, not our backend. The Flutter app signs in with
`supabase_flutter`, which issues a **JWT**. Every request to FastAPI carries that token; the
backend **verifies it** (JWKS / signing config, issuer, audience, expiry) and maps
`token.sub` → `users.auth_user_id` → `users.id`. There is **no product-path password or OTP
handling in our API** — that belongs to Supabase.

- **Login brute-force protection** is Supabase Auth rate limiting (dashboard). See
  [`rate_limiting.md`](./rate_limiting.md).
- **Admin portals** use Supabase Auth + **AAL2 / MFA** (`require_admin_aal2`).
- **Step-up** on irreversible self-service actions: account deletion requires email confirm +
  current password (wrong password → **403**, never 401, so mobile does not treat it as session death).

**Takeaway:** identity comes from a cryptographically signed token the client cannot forge — not
from anything the client merely *claims*.

---

## 2. Authorization — what you can reach

This layer stops **user A from reading user B's data**. Golden rule:

> **Every resource access is keyed to the authenticated `current_user.id` from the token — never to
> an id the client supplies for ownership.**

That avoids **IDOR**. Concretely:

| Area | How access is enforced |
|---|---|
| **Messages / conversations** | REST and WebSocket go through conversation membership checks → **404** if you are not a member. Subscribe and send are re-authorized. |
| **Profiles** | Visibility / block checks → **404** (not 403) when hidden or blocked. |
| **Groups** | Private groups **404** to non-members; member lists require active membership. |
| **Notifications** | Scoped to `current_user.id`. |
| **Connections** | Accept/decline only if `receiver_id == current_user.id`. |
| **Admin** | `require_admin_aal2`; sensitive actions write `AdminAuditLog` (including report view/resolve and suspensions with reason). |
| **Account** | Deletion and export are self-only; export is audited as `account.export`. |

### Why this is safe

1. Authz keyed to token identity, not client-supplied ownership.
2. Resource ids are UUIDs — not enumerable; a guessed id still fails membership/visibility.
3. **404, not 403**, for private things — probing cannot confirm existence.
4. Tests + OpenAPI/route inventory snapshots guard against unguarded routes.

**Unauthenticated surfaces** are intentionally narrow (e.g. public lookups, health, branded auth
email hooks with signature verification, employer registration with IP rate limits) — never
arbitrary user data.

---

## 3. Realtime messaging security

Chat is **FastAPI WebSockets** (`/api/v1/ws`), not Supabase Realtime:

1. Authenticate with a short-lived Supabase access token (first frame).
2. Authorize every `conversation.subscribe` and `message.send`.
3. Persist to PostgreSQL, then publish for live delivery (Redis Pub/Sub when `REDIS_URL` is set;
   otherwise in-process fan-out on a single instance).
4. On block / suspend, control events revoke live sockets (cross-instance via Redis control channel
   when configured).

Missed live events are recovered with REST history / sync — Redis is **not** message history.

---

## 4. Encryption — how data is protected

| Layer | What we have |
|---|---|
| **In transit** | **TLS** — HTTPS for the API, WSS for the WebSocket. |
| **At rest** | Postgres/Supabase encrypts at the disk level. |
| **Access-controlled** | Only conversation members can read via API; blocks enforced. |
| **Database-level** | Supabase **RLS** remains defense-in-depth if anything ever hits Postgres with the anon key (see [`rls_messages.md`](./rls_messages.md)). Chat delivery itself does **not** go through Realtime. |

### Are messages end-to-end encrypted? No — deliberately.

**E2EE** would prevent the server from ever reading bodies. We need server visibility for:

- report **evidence snapshots**,
- **admin moderation**,
- campus safety / harassment response,

So the model is **TLS + at-rest encryption + strict access control + moderation visibility**.

**Insider caveat:** plaintext bodies in the DB are readable with direct DB access. Mitigate by
tight production DB access; optional future hardening is column encryption with a server-held key
(still moderation-compatible, unlike E2EE).

---

## 5. Production hardening (backend)

| Control | Behavior |
|---------|----------|
| OpenAPI UI | `/docs`, `/redoc`, `/openapi.json` **disabled** when `ENVIRONMENT` is production |
| Security headers | nosniff, `X-Frame-Options: DENY`, CSP, Referrer-Policy; **HSTS** in production only |
| Correlation | `X-Request-ID` on responses; stamped into audit `after_data` when present |
| Body size | Edge middleware rejects oversized `Content-Length` early |
| Readiness | `/health/ready` probes DB (and Redis when `REDIS_URL` is set) |

---

## 6. Secrets

`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`, DB passwords, `FIREBASE_CREDENTIALS_JSON`,
Redis credentials, webhook secrets — live only in `.env` (gitignored) / the deploy secret store,
never in the repo. RLS *policy SQL* is safe to commit; secret *values* are not.
