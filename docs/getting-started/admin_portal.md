# Admin portal (Next.js) — first admin + local run

Use this once to create a real administrator, then daily to run the admin UI.

The admin app lives in [`admin/`](../../admin/) and signs in with **Supabase Auth**
(email + password + MFA). FastAPI still authorizes every `/admin` call via
`users.role = admin` and JWT `aal=aal2`.

---

## Create the first admin (Super Admin bootstrap)

Admin access has two layers: `users.role = admin` (the base gate, checked by every `/admin`
call) plus a **scope** — `super_admin` / `school_admin` / `honors_admin` / `content_admin` /
`auditor` — recorded in the `admin_memberships` table (see `app/features/admin/admins.py`).
Scopes control what an admin can actually do (e.g. only `honors_admin` sees Scholars/Employers;
only `super_admin`/`school_admin` can invite other admins).

Run this **exactly once**, to create the one and only Super Admin — every admin after this is
created through the in-app invite flow (Admins & Roles page → "Invite an admin"), never by
running a script again:

```bash
cd backend
source .venv/bin/activate
python scripts/create_admin.py
```

It prompts for an email + display name, invites them through Supabase Auth (a real email, via
LC Connect's own branded sender — never a script-set password), and seeds the `super_admin`
scope. It refuses to run again once any `super_admin` exists.

If the email you enter already has a Supabase identity (e.g. an existing student/staff account
being promoted), no invite email is sent — the script grants Super Admin directly, and you sign
in with the password you already use.

Then:
1. Check the invite email (or sign in directly, if promoting an existing account).
2. **Enroll MFA (TOTP)** — the admin login flow walks you through enroll/verify on first login.
   Admin APIs reject tokens that are only `aal1`.
3. Open the admin app and sign in.

Forgot your password later? Use **"Forgot your password?"** on the login page
(`/forgot-password` → `/reset-password`) — same self-service flow as the invite, no dashboard
access needed.

There is no separate "super admin password." The password is the Supabase Auth password; admin
power comes from `role=admin` + a scope + MFA.

### Legacy: `promote_admin.py`

`scripts/promote_admin.py` predates the scoped-admin system — it only sets the flat
`users.role = 'admin'` column and grants **no scope at all**. An account promoted this way can
sign into the admin portal but won't see any Honors/Admins-invite functionality. Prefer
`create_admin.py` (bootstrap) or an in-app invite (every subsequent admin) instead.

---

## Run the admin app locally

```bash
# Terminal A — API (from repo)
cd backend && source .venv/bin/activate
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Terminal B — Admin UI
cd admin
cp .env.local.example .env.local   # once — fill Supabase + API URL
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

Required env (see `admin/.env.local.example`):

- `NEXT_PUBLIC_SUPABASE_URL` — same as mobile
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — same as mobile anon key
- `NEXT_PUBLIC_API_BASE_URL` — e.g. `http://localhost:8000/api/v1`

Never put the Supabase **service role** key in the Next.js app.

---

## Legacy note

[`admin_web/`](../../admin_web/) was a temporary token-paste tool. Prefer this Next.js app.
