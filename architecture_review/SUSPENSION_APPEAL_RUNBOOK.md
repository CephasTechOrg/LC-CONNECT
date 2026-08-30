# Suspension appeal workflow runbook

**Enterprise review #22** — user-facing path when an account is suspended.

## What happens on suspend

1. Admin calls `POST /admin/users/{id}/suspend` with a **required reason** (audit trail).
2. Backend sets `users.status = 'suspended'`, `is_active = false`, audits, and disconnects live WebSockets.
3. Mobile/API auth guards block normal app use. Bootstrap and protected routes return **403** with machine-readable detail `account_suspended` (not a generic 401).

## What the suspended user can do

| Surface | Behavior |
|---------|----------|
| **Mobile** | Stays signed in to Supabase; routed to `/suspended`. Can submit **one open appeal** or email support. Does **not** auto-reactivate. |
| **API** | `GET /account/suspension-status`, `POST /account/suspension-appeal` (JWT valid, account suspended only). Rate limit: 3 appeals / day / user. |
| **Support email** | `SUPPORT_EMAIL` env (default `support@livingstone.edu`) shown on status + mobile screen. |

## Admin review

1. **Moderation** page → **Open suspension appeals** table (from `GET /admin/suspension-appeals?status=open`).
2. **Mark resolved** — appeal closed, optional note, audit `suspension_appeal.resolved`.
3. **Dismiss** — appeal closed without agreeing, audit `suspension_appeal.dismissed`.
4. **Reactivate** (if appropriate) — separate action on **Users**: `POST /admin/users/{id}/reactivate`. Resolving an appeal does **not** reactivate.

## Data model

Table `suspension_appeals`: `user_id`, `message`, `status` (`open` \| `dismissed` \| `resolved`), `admin_note`, `reviewed_by_id`, timestamps.

## Mobile re-entry after reactivation

User taps **Check if account was restored** on the suspended screen (retries bootstrap). If admin reactivated, they proceed through normal verify/onboarding routing.

## Config

```bash
SUPPORT_EMAIL=support@livingstone.edu   # optional override
```

## Migration

```bash
cd backend && .venv/bin/alembic upgrade head
```

Revision: `b1c2d3e4f5a6_add_suspension_appeals.py`

## Tests

```bash
cd backend
.venv/bin/pytest tests/db/test_suspension_appeals.py tests/test_auth_guards.py
```
