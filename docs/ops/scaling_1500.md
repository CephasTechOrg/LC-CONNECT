# Scaling readiness — campus pilot (≤ ~1,500 users)

**Audience:** whoever deploys or watches Render for LC Connect.  
**Architecture source of truth:** `architecture_review/` (especially ADR-003 / Redis, WebSocket messaging).

This note is **ops guidance**, not a license to add Redis caching or change the chat stack.

---

## Target shape

| Piece | Campus pilot (single API instance) | Before 2+ API workers |
|-------|------------------------------------|------------------------|
| Postgres | Truth for all domain data | Same |
| Redis | **Optional** — leave `REDIS_URL` unset | **Required** for WS fan-out + distributed rate limits |
| Message history | Postgres only | Never in Redis (locked) |
| Response cache | None (in-process JWKS / policy caches only) | Still no general Redis response cache |

At ~1,500 active students on one Render web service, in-process token buckets and local WS fan-out are enough. Redis becomes a correctness requirement when you scale **horizontally**, not when you hit a magic user count.

---

## When to set `REDIS_URL`

Set it **before** you run a second FastAPI instance (or raise Render `numInstances` / autoscaling above 1).

Without Redis on multi-instance:

- WebSocket events published on instance A do not reach subscribers on instance B.
- Per-user rate limits (`aallow`) are process-local → effective limits multiply by instance count.
- Typing / presence TTLs are not shared across workers.

With Redis connected, `app/shared/rate_limit.py` and the realtime event bus share state; if Redis blips, rate limits **fall back to memory** (logged) so the API stays up — fan-out may miss cross-instance delivery until Redis recovers.

**Ready check:** `GET /health/ready` (see API readiness) should stay green after Redis is wired. Confirm in Render logs that the Redis client connects on boot.

---

## Rate limits (do not blunt-global)

Prefer the **existing per-action** caps in `backend/app/config.py` / `app/shared/rate_limit.py` over a single “20 req/s per user” gate.

| Concern | Where |
|---------|--------|
| Login / signup abuse | Supabase Auth dashboard |
| Connection / group / report spam | Daily REST buckets |
| Chat send / reactions / edits | Per-minute REST + WS send/typing limits |
| Anonymous floods | Edge (Cloudflare / Render) — only if abuse appears |

Details and env vars: [`docs/security/rate_limiting.md`](../security/rate_limiting.md).

`GROUP_MAX_MEMBERS` (default 500) caps per-message fan-out cost; leave it unless product raises group size on purpose.

---

## Watching latency (no APM required for pilot)

Every request gets an `X-Request-Id` (middleware in `app/shared/request_context.py`). Logs look like:

```text
INFO:     [lc_connect…] [req=<uuid>] …
```

In Render → `lc-connect` → Logs:

1. Filter by `req=` when a student reports a slow action.
2. Watch p95 informally for paths that matter most: `/discover`, `/messages/*`, WebSocket connect/send.
3. If discovery or employer scholar list stay slow under load, add **targeted** timing logs in those list handlers — not a Redis cache first.

---

## Checklist before raising instance count

- [ ] `REDIS_URL` set on the API service (managed Redis or Render Key Value)
- [ ] Deploy + confirm Redis connect log; `/health/ready` OK
- [ ] Spot-check: two devices on different connections still receive DM / group events
- [ ] Confirm 429s still fire under abuse (limits are shared, not doubled)
- [ ] Re-read `architecture_review/PHASE_0_1_STATUS.md` for any Redis caveats

---

## Related

| Doc | Topic |
|-----|--------|
| [`architecture_review/PRODUCTION_SETUP_CHECKLIST.md`](../../architecture_review/PRODUCTION_SETUP_CHECKLIST.md) | Env vars, deploy |
| [`docs/security/rate_limiting.md`](../security/rate_limiting.md) | Buckets + 429 UX |
| [`architecture_review/03_fastapi_websocket_messaging.md`](../../architecture_review/03_fastapi_websocket_messaging.md) | WS + Redis fan-out |
