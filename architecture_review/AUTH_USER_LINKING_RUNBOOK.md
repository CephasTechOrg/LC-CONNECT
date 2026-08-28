# Auth user linking runbook (#25)

Formal procedure to ensure every **live** LC Connect account has `users.auth_user_id`
pointing at a Supabase Auth subject (`auth.users.id`). Soft-deleted tombstones may keep
`auth_user_id` NULL (account deletion unlinks on purpose).

## Prerequisites

- Backend env: `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
- Product auth path is already Supabase-only (legacy password/OTP routers removed)
- Run against the **same** Supabase project the API uses

## How linking works

| Situation | What happens |
|-----------|----------------|
| User signs in / registers via app | `POST /auth/bootstrap` links or creates the row by email |
| Historical row, Supabase account already exists | Script looks up Auth by email and sets `auth_user_id` |
| Historical row, no Supabase account yet | User must register (or ops invite); bootstrap links on first login |
| Soft-deleted user | Leave `auth_user_id` NULL — do not re-link |

Never write passwords into Supabase Auth tables by hand.

## Steps

### 1. Backup

Take a DB snapshot / confirm point-in-time recovery before any `--apply` on production.

### 2. Dry-run report

```bash
cd backend
.venv/bin/python scripts/link_auth_users.py
```

Exit code `0` means every live user either already has `auth_user_id` or matches an Auth
email that can be linked. Exit code `1` lists emails still missing in Supabase or conflicts.

### 3. Apply links

```bash
.venv/bin/python scripts/link_auth_users.py --apply
```

Re-run the dry-run until the gate prints **OK**.

### 4. Clear “missing in Supabase”

For each remaining live email:

1. Prefer: ask the person to **sign up / sign in** in the app (bootstrap links automatically), or
2. Ops: invite via admin/employer flows where appropriate (`invite_auth_user`), then re-run `--apply`

Do **not** invent Auth users with shared passwords.

### 5. Spot-check SQL

```sql
-- Live accounts still unlinked (should be 0 before #20)
SELECT id, email, role, status
FROM users
WHERE auth_user_id IS NULL
  AND deleted_at IS NULL
  AND status <> 'deleted';

-- Tombstones may remain unlinked
SELECT count(*) FROM users WHERE deleted_at IS NOT NULL AND auth_user_id IS NULL;
```

### 6. Gate for #20 (drop credential columns)

Only after dry-run/apply reports **Gate OK**:

1. Confirm no product code reads `password_hash` / `*_otp_*` (already true post-migration).
2. Apply Alembic migration that drops those columns (see #20).
3. Deploy backend that matches the new model.

## Rollback

- Linking is additive (`auth_user_id` set). To undo a bad link: set that row’s
  `auth_user_id` back to NULL **only** if you are sure no sessions rely on it, then fix Auth.
- Column drop (#20) is irreversible without restore from backup — keep the backup until
  pilot confirms login for a sample of students, staff, and admins.

## Related

- `backend/app/shared/auth_linking.py` — link logic
- `backend/scripts/link_auth_users.py` — CLI
- `backend/app/features/auth/service.py` — runtime bootstrap
- `architecture_review/02_supabase_auth_migration.md` — original plan
