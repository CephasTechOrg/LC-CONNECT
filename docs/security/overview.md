# Security & Authorization — Overview

How LC Connect keeps user data safe: **who you are** (authentication), **what you can reach**
(authorization), and **how data is protected** (encryption). Written to be understood, not just
skimmed — a reviewer or a new developer should be able to trust the model after reading this.

Companion docs: [`rls_messages.md`](./rls_messages.md) (database-level RLS), [`rate_limiting.md`](./rate_limiting.md)
(abuse limits), [`audit_and_data_retention.md`](./audit_and_data_retention.md) (deletion & evidence).

---

## 1. Authentication — who you are

Login runs on **Supabase Auth**, not our backend. The Flutter app signs in against Supabase
(`supabase_flutter`), which issues a **JWT**. Every request to our FastAPI backend carries that
token; the backend **verifies it** (signature + audience) and resolves the current user. There is
no password handling in our API — that's Supabase's job.

- Because login lives in Supabase, **login brute-force protection is Supabase's built-in rate
  limiting** (dashboard-configurable). See [`rate_limiting.md`](./rate_limiting.md).
- **Legacy custom-password auth** (`app/routers/auth.py`: `/auth/login`, `/register`,
  `/forgot-password`, `/reset-password`) still exists as a **rollback surface**. The mobile app no
  longer uses it (it signs in via Supabase Auth). It is now **mounted only when
  `AUTH_LEGACY_ENABLED=true`** — set that flag to **`false`** (safe, since the app is on Supabase) to
  remove these unauthenticated password endpoints entirely. **While enabled they have no rate
  limiting**, so leaving the flag on is a brute-force / email-bomb surface — disable it.

**Takeaway:** the identity in every request comes from a cryptographically-signed token the client
can't forge — not from anything the client *claims*.

---

## 2. Authorization — what you can reach

This is the layer that stops **user A from reading user B's data**. The golden rule across the whole
API:

> **Every resource access is keyed to the authenticated `current_user.id` from the token — never to
> an id the client supplies for ownership.**

That single principle avoids **IDOR** (Insecure Direct Object Reference — "just change the id in the
URL"), the most common access-control bug. Concretely:

| Area | How access is enforced |
|---|---|
| **Messages / conversations** | Every read/write goes through `accessible_conversation(id, current_user.id)` → resolves the id **and** checks active membership → **404** if you're not a member. Passing someone else's `match_id`/`conversation_id` returns nothing. The WebSocket authorizes subscribes the same way. |
| **Profiles** | `GET /users/{id}` runs `assert_profile_visible` → **404** if hidden, verified-only-and-you're-not, or blocked (either direction). |
| **Groups** | Private groups **404** to non-members (existence never revealed); member/request lists require active membership; group messages use the same `accessible_conversation` gate. |
| **Notifications** | Every endpoint is scoped to `current_user.id` — you can't read or clear anyone else's. |
| **Connections** | Accept/decline check `request.receiver_id == current_user.id`; you can't act on someone else's request. |
| **Admin** | `GET /admin/reports` etc. require `require_admin_aal2` (admin + step-up auth). |

### Why this is safe (the design that prevents IDOR)

1. **Authz keyed to the token identity, not client input** — the classic mistake is avoided everywhere.
2. **Resource ids are UUIDs** — not enumerable (`1, 2, 3…`), and a *guessed* id still fails the
   membership/visibility check.
3. **404, not 403, for private things** — so probing can't even confirm a private group or hidden
   profile exists.
4. **Tested:** the DB suite asserts the deny cases (non-member → 404, plain member can't delete
   another's message, outsider can't access a group conversation), and the OpenAPI snapshot +
   route-inventory tests fail CI if anyone adds an unexpected/unguarded route.

**The only unauthenticated endpoint** is `GET /lookups` — it returns static dropdown data
(interest/language lists), never user data.

---

## 3. Encryption — how data is protected

| Layer | What we have |
|---|---|
| **In transit** | **TLS** everywhere — HTTPS for the API, WSS for the WebSocket. Nobody on the network can read traffic. |
| **At rest** | Postgres/Supabase encrypts data at rest at the disk level. |
| **Access-controlled** | Only conversation members can read a message via the API; blocks are enforced. |
| **Database-level** | Supabase **Row-Level Security** guards any *direct* Supabase access with the app's anon key (see [`rls_messages.md`](./rls_messages.md)). |

### Are messages end-to-end encrypted? No — and deliberately so.

**E2EE** means only sender + recipient can *ever* read a message — the server cannot. Ours can (message
bodies are stored so they can be served, moderated, and snapshotted for reports). That is a **conscious
choice**, because E2EE is **incompatible with the safety mission** of a moderated campus platform:

- report **evidence snapshots** (a reported message's text preserved so moderation survives deletion),
- **admin moderation** of group content,
- the whole "students report harassment, staff act on it" model,

all require the server to see content. WhatsApp is E2EE and *famously cannot* moderate — the opposite
of what LC Connect wants. So the correct model here is **TLS + at-rest encryption + strict
access-control + moderation visibility**, which is what we have.

**Insider/DB-access caveat:** because bodies are plaintext in the DB, someone with **direct database
access** could read them. Mitigation is limiting who has production DB access; optional future
hardening is column-level encryption of message bodies with a server-held key (which keeps moderation
working, unlike E2EE).

---

## 4. Secrets

Secret values — `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`, `JWT_SECRET_KEY`, DB passwords,
`FIREBASE_CREDENTIALS_JSON` — live only in `.env` (gitignored) / the deploy platform's secret store,
never in the repo. RLS *policy SQL* is safe to commit (security comes from enforcement, not secrecy);
secret *values* are not.
