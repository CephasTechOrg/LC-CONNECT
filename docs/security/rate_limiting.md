# Rate Limiting & Abuse Prevention

Two different jobs, two different homes:

1. **Login / signup brute-force → Supabase Auth** (dashboard config).
2. **A signed-in user spamming expensive actions → our backend** (per-user limits).

Keeping them separate matters: login doesn't run through our API, so trying to rate-limit it in
FastAPI would do nothing.

---

## 1. Login limits — Supabase Auth

Because authentication happens on Supabase (the app talks to Supabase Auth directly, our backend only
verifies the resulting JWT — see [`overview.md`](./overview.md)), **login/signup/OTP/password-reset
rate limiting is Supabase's built-in feature**, tuned in the dashboard:

> **Supabase Dashboard → Authentication → Rate Limits**

Review/tighten there:
- **sign-in attempts** per IP (the brute-force guard),
- **email sends** (sign-up / magic-link / password-reset — prevents inbox bombing),
- **token refresh** and **OTP** limits.

Nothing to build for this — just configure it.

---

## 2. Per-user abuse limits — our backend

Our REST endpoints are all JWT-gated, so they aren't *login*-brute-forceable. The remaining risk is a
**logged-in user spamming** expensive or abusable actions. We cap those per user.

### How it works

- A **token bucket per `(action, user_id)`** ([`app/shared/rate_limit.py`](../../backend/app/shared/rate_limit.py)):
  a user may **burst up to the limit**, then refills to a sustained ~limit-per-window.
- Applied as a FastAPI **dependency** (`UserRateLimit`) via route `dependencies=[...]` — it doesn't
  change the endpoint's logic or its OpenAPI schema.
- Over the limit → **HTTP 429** with a friendly, user-facing `detail` message. The mobile app surfaces
  that message directly (see the 429 UX below).
- **`allow()`** is process-local memory (fine for conn-scoped keys). **`aallow()`** uses Redis when
  `REDIS_URL` is connected (shared across instances) and falls back to memory on outage / when Redis
  is unset. WebSocket send/typing and HTTP abuse limits use `aallow`.

### The limits (per user, per day)

Generous enough that a real student never hits them; tight enough to stop abuse. **All are
env-configurable** — defaults live in [`app/config.py`](../../backend/app/config.py).

| Action | Default / day | Env var |
|---|---|---|
| Connection requests | **50** | `RATE_LIMIT_CONNECTION_REQUESTS_PER_DAY` |
| Group creation | **5** | `RATE_LIMIT_GROUP_CREATES_PER_DAY` |
| Avatar uploads (profile + group combined) | **10** | `RATE_LIMIT_AVATAR_UPLOADS_PER_DAY` |
| Reports | **20** | `RATE_LIMIT_REPORTS_PER_DAY` |
| Group invites | **200** | `RATE_LIMIT_GROUP_INVITES_PER_DAY` |

Also here: **`GROUP_MAX_MEMBERS`** (default 500) — the global hard cap on group size, which bounds
per-message fan-out cost. To change any value, set the env var (in `.env` locally or the deploy
platform's env) and **restart the backend**.

### Endpoints covered

`POST /connections/request` · `POST /groups` · `POST /profiles/me/avatar` · `POST /groups/{id}/avatar`
· `POST /reports` · `POST /groups/{id}/invites`.

---

## 3. The 429 UX (mobile)

Errors must read clearly to users. The app's [`apiErrorMessage`](../../mobile/lib/core/api/api_error.dart)
helper pulls the backend's own `detail` out of a failed call, so a rate-limit hit shows exactly what
the server says — e.g. *"You've sent too many connection requests today — try again tomorrow."* —
instead of a generic error. It also maps timeouts/offline to *"No connection — check your internet."*
and never surfaces a raw exception. Wired into every rate-limited action (connect, join, create,
avatar, report, invite).

---

## 4. Not covered (deferred)

- **IP/edge rate limiting** (crude flood protection before requests reach the app) — best done at
  Render/Cloudflare when needed.
- **Redis-backed** distributed buckets — needed only when running multiple API workers.
- **WebSocket** message/typing/subscribe already have their own limiters (see the realtime docs).
