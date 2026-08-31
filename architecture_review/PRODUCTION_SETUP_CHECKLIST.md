# Production setup checklist

**Use this before first production launch and after any change that adds migrations, env vars, or cron jobs.**

Last updated: 2026-08-30 (includes suspension appeals #22, message retention cron #21).

---

## Quick reference — what runs where

| Component | Host | Config source |
|-----------|------|----------------|
| FastAPI API | Render `lc-connect-api` | Root [`render.yaml`](../render.yaml) + Render dashboard secrets |
| Admin portal | Render `lc-connect-admin` | `render.yaml` + `NEXT_PUBLIC_*` at **build** time |
| Employer portal | Render `lc-connect-employer` | Same as admin |
| Flutter mobile | App Store / Play Store | `mobile/.env` / CI secrets (`SUPABASE_URL`, API base URL) |
| PostgreSQL | Supabase | `DATABASE_URL` on API (transaction pooler, port **6543**) |
| Auth + email hook | Supabase | Send Email hook → API `/auth/hooks/send-email` |
| Message purge cron | Render cron **or** GitHub Actions | [`MESSAGE_RETENTION_CRON_RUNBOOK.md`](./MESSAGE_RETENTION_CRON_RUNBOOK.md) |

**Schema migrations:** automatic on every API deploy — `alembic upgrade head` is in the API `startCommand` (see `render.yaml`). You do **not** run Alembic manually on Render unless debugging a failed deploy.

---

## 1. API service (`lc-connect-api`) — required secrets

Set in **Render → lc-connect-api → Environment**. Declared in `render.yaml` with `sync: false` where secret.

| Variable | Required | Notes |
|----------|----------|--------|
| `DATABASE_URL` | **Yes** | Supabase **Transaction pooler** URL (port **6543**). See [`deployment.md`](../docs/getting-started/deployment.md) §5. |
| `SUPABASE_URL` | **Yes** | Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | **Yes** | Storage, admin user ops, password step-up |
| `SUPABASE_JWT_SECRET` | If HS256 | RS256 projects can use JWKS from `SUPABASE_URL` alone |
| `JWT_SECRET_KEY` | Legacy only | Only if `AUTH_LEGACY_ENABLED=true` (should be off) |
| `CORS_ORIGINS` | **Yes** | e.g. `*` for mobile-only MVP |
| `ADMIN_PORTAL_URL` | **Yes** (once admin deployed) | Invite/reset links for admin app |
| `EMPLOYER_PORTAL_URL` | **Yes** (once employer deployed) | Invite links for employer app |
| `RESEND_API_KEY` | **Yes** (real email) | Without it, auth emails log to console only |
| `RESEND_FROM_EMAIL` | **Yes** (real email) | Verified domain in Resend |
| `SUPABASE_SEND_EMAIL_HOOK_SECRET` | **Yes** (if hook enabled) | Supabase Auth → Hooks → Send Email |
| `FIREBASE_CREDENTIALS_JSON` | Optional | Whole service-account JSON; push disabled if unset |

**Must NOT be set in production:**

| Variable | Why |
|----------|-----|
| `DEV_TEST_EMAILS` | App **refuses to start** if non-empty when `ENVIRONMENT=production` |

---

## 2. API service — optional / feature env (set explicitly so you don't forget)

| Variable | Default | When to override |
|----------|---------|------------------|
| `SUPPORT_EMAIL` | `support@livingstone.edu` | **Set to your real student-support inbox** before launch — shown on suspended-user screen and `GET /account/suspension-status`. |
| `MESSAGE_SOFT_DELETE_RETENTION_DAYS` | `90` | Only change after policy review; used by retention cron. |
| `REDIS_URL` | unset | **Deferred** until 2+ API instances — see `PHASE_0_1_STATUS.md` |
| `RESEND_REPLY_TO` | unset | Support inbox for email replies |
| `ALLOWED_EMAIL_DOMAINS` | `students.livingstone.edu,livingstone.edu` | Campus signup policy |

Both optional vars are declared in [`render.yaml`](../render.yaml) with safe defaults so new environments get them without a manual step.

---

## 3. Admin + employer portals

Each Next.js service needs these **before build** (Render supplies at build + runtime):

| Variable | Example |
|----------|---------|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://xxxxx.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key (never service role) |
| `NEXT_PUBLIC_API_BASE_URL` | `https://lc-connect-api.onrender.com/api/v1` |

After deploy, set on the **API** service:

- `ADMIN_PORTAL_URL` → deployed admin URL (e.g. `https://lc-connect-admin.onrender.com`)
- `EMPLOYER_PORTAL_URL` → deployed employer URL

**Suspension appeals:** no extra portal env — open appeals appear on **Moderation** after deploy. Train moderators: resolve/dismiss appeal **≠** reactivate (Users page).

Runbook: [`SUSPENSION_APPEAL_RUNBOOK.md`](./SUSPENSION_APPEAL_RUNBOOK.md)

---

## 4. Supabase dashboard (one-time)

- [ ] **Send Email** auth hook enabled → points to production API hook URL + `SUPABASE_SEND_EMAIL_HOOK_SECRET` on API
- [ ] **Site URL** / redirect URLs include admin + employer `accept-invite` paths
- [ ] **Storage buckets:** `profile-images` (public), `scholar-private` (private) if Scholars is live
- [ ] **MFA** enforced for admin accounts (admin API requires `aal2`)
- [ ] Transaction pooler connection string copied to Render `DATABASE_URL`

---

## 5. Scheduled jobs (not automatic — must create once)

| Job | Runbook | Status |
|-----|---------|--------|
| Soft-deleted message purge (daily) | [`MESSAGE_RETENTION_CRON_RUNBOOK.md`](./MESSAGE_RETENTION_CRON_RUNBOOK.md) | **Create Render cron or GitHub Action** — not in `render.yaml` yet |

Suspension appeals do **not** need a cron job (in-app + admin UI only).

---

## 6. Mobile app release

- [ ] Production `SUPABASE_URL` + anon key in build config / CI
- [ ] API base URL points to production Render API (`…/api/v1`)
- [ ] No code change needed for `SUPPORT_EMAIL` — loaded from API at runtime on suspend screen
- [ ] Ship a build **after** API deploy so `/suspended` route and appeal endpoints exist

---

## 7. Post-deploy smoke tests

Run once after each production deploy (or use as a launch gate):

### API health

```bash
curl -s https://YOUR-API.onrender.com/health
curl -s https://YOUR-API.onrender.com/health/ready
```

### Schema (suspension appeals table)

Confirm deploy logs show `alembic upgrade head` succeeded. Optional — list routes include:

- `GET /api/v1/account/suspension-status`
- `POST /api/v1/account/suspension-appeal`
- `GET /api/v1/admin/suspension-appeals`

### Suspension flow (staging or test account)

1. Suspend a test user from admin **Users** or **Moderation** (reason required).
2. Open mobile app as that user → lands on **Account suspended**, not logged out.
3. Submit appeal → appears in admin **Moderation → Open suspension appeals**.
4. Dismiss or resolve appeal → audit log `suspension_appeal.*`.
5. **Reactivate** on Users → user taps **Check if account was restored** → normal app access.

### Message retention (after cron is configured)

```bash
cd backend
PYTHONPATH=. python scripts/purge_soft_deleted_messages.py   # dry-run
```

---

## 8. Deploy checklist (copy before every release)

### Code / CI

- [ ] `main` green: unit tests + `tests/db` (CI Postgres)
- [ ] `python scripts/check_line_limits.py` passes
- [ ] OpenAPI snapshot updated if API changed (`UPDATE_SNAPSHOTS=1 pytest` from `backend/`)

### Render

- [ ] Push to `main` (auto-deploy) or manual deploy all three web services
- [ ] Verify API logs: `alembic upgrade head` OK, no `ValidationError` on startup
- [ ] `SUPPORT_EMAIL` set to real inbox (if not using default)
- [ ] Message retention cron still scheduled (if already created)

### Portals

- [ ] Admin Moderation loads; suspension appeals section visible when appeals exist
- [ ] `ADMIN_PORTAL_URL` / `EMPLOYER_PORTAL_URL` on API match live portal URLs

### Mobile

- [ ] Store build submitted if this release includes client changes

---

## Related docs

| Doc | Topic |
|-----|--------|
| [`docs/getting-started/deployment.md`](../docs/getting-started/deployment.md) | Render web service details, troubleshooting |
| [`SUSPENSION_APPEAL_RUNBOOK.md`](./SUSPENSION_APPEAL_RUNBOOK.md) | Suspend / appeal / reactivate workflow |
| [`MESSAGE_RETENTION_CRON_RUNBOOK.md`](./MESSAGE_RETENTION_CRON_RUNBOOK.md) | Daily purge cron |
| [`AUTH_USER_LINKING_RUNBOOK.md`](./AUTH_USER_LINKING_RUNBOOK.md) | `auth_user_id` backfill (#25) |
| [`backend/.env.example`](../backend/.env.example) | Full local env reference |
