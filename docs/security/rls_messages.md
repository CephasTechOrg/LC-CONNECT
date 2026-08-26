# Messages Table — Row Level Security (RLS)

**Status:** Still useful as **defense-in-depth** for any direct Postgres access with the Supabase
anon key.  
**Chat delivery path (current):** FastAPI WebSockets — **not** Supabase Realtime. See
[`architecture_review/03_fastapi_websocket_messaging.md`](../../architecture_review/03_fastapi_websocket_messaging.md).

---

## Why RLS still matters

The Flutter app may embed the project's **anon key** (it is not a secret — extractable from an
APK/IPA). Without Row Level Security, that key could allow unrestricted reads/writes against
tables exposed to PostgREST, bypassing FastAPI.

RLS enforces access **in PostgreSQL** regardless of how a client connects. Even with the anon key,
a caller only sees rows the policies allow.

**Policy SQL is safe to commit.** Secret *values* (`SUPABASE_SERVICE_ROLE_KEY`, DB passwords, etc.)
must never be.

---

## Current auth model (do not confuse with older Realtime docs)

| Plane | Role |
|-------|------|
| **Supabase Auth** | Issues the user JWT (login / session / MFA). |
| **FastAPI** | Verifies the JWT, authorizes REST + WebSocket, persists messages, fans out live events. |
| **Redis (optional)** | Cross-instance Pub/Sub + distributed rate limits when `REDIS_URL` is set. |
| **Supabase Realtime** | **Not** used for product chat. Older docs that describe JWT-into-Realtime wiring are historical. |

Flutter chat uses the FastAPI WebSocket client (`mobile/lib/core/realtime/`). Message **history and
sync** use FastAPI REST. RLS does not replace those checks — it is a second fence if something ever
hits the database outside FastAPI.

---

## Historical note

Earlier LC Connect builds delivered chat via Supabase Realtime and wired a custom FastAPI JWT into
Realtime so `auth.uid()` worked in policies. That design is **retired**. Keep RLS policies maintained
for defense-in-depth; do not reintroduce Realtime as the chat plane.

If you need the old Realtime wiring narrative for archaeology, see git history of this file before
2026-08-26 — not the live architecture.
