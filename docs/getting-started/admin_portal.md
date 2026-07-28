# Admin portal (Next.js) — first admin + local run

Use this once to create a real administrator, then daily to run the admin UI.

The admin app lives in [`admin/`](../../admin/) and signs in with **Supabase Auth**
(email + password + MFA). FastAPI still authorizes every `/admin` call via
`users.role = admin` and JWT `aal=aal2`.

---

## Create the first admin

1. **Create the Auth user** in Supabase Dashboard → Authentication → Users  
   (or sign up once in the mobile app with a `@livingstone.edu` email).  
   Set a strong password. Confirm the email if required.

2. **Bootstrap the app user** — sign in once (mobile or the admin login page) so
   `POST /api/v1/auth/bootstrap` creates the `users` row. For `@livingstone.edu`
   the role will be `staff` until you promote.

3. **Promote to admin** (from `backend/` with venv active):

```bash
cd backend
source .venv/bin/activate
python scripts/promote_admin.py you@livingstone.edu
```

4. **Enroll MFA (TOTP)** for that Supabase user (Authenticator app).  
   The Next.js admin login flow supports enroll/verify. Admin APIs reject tokens
   that are only `aal1`.

5. Open the admin app and sign in with that email + password, then MFA.

There is no separate “super admin password.” The password is the Supabase Auth
password; admin power is `role=admin` + MFA.

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
The old `backend/scripts/create_admin.py` creates legacy password-hash admins — use
`promote_admin.py` for the Supabase path instead.
