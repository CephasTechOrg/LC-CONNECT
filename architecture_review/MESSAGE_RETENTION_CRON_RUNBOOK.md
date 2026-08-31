# Message retention cron runbook (#21)

Daily job that **hard-deletes** soft-deleted messages older than the retention window.
Report evidence (`reports.message_body`) is **not** purged.

**Policy reference:** [`docs/security/audit_and_data_retention.md`](../docs/security/audit_and_data_retention.md)

**Production:** this cron is **not** created automatically — add it once using this runbook, then check it off in [`PRODUCTION_SETUP_CHECKLIST.md`](./PRODUCTION_SETUP_CHECKLIST.md) §5.

---

## Quick reference

| Item | Value |
|------|--------|
| Script | `backend/scripts/purge_soft_deleted_messages.py` |
| Default window | **90 days** (`MESSAGE_SOFT_DELETE_RETENTION_DAYS`) |
| Schedule | **Once per day** (off-peak UTC recommended) |
| Workers / Redis | **Not required** — cron + script is enough for MVP |

```bash
cd backend
.venv/bin/python scripts/purge_soft_deleted_messages.py          # dry-run (safe)
.venv/bin/python scripts/purge_soft_deleted_messages.py --apply  # delete eligible rows
```

---

## Prerequisites

The cron job needs the **same env as the API** for database access:

| Variable | Required |
|----------|----------|
| `DATABASE_URL` | Yes — Supabase transaction pooler (`:6543`) in production |
| `MESSAGE_SOFT_DELETE_RETENTION_DAYS` | Optional — defaults to `90` |

No Supabase service role key is required for purge (DB only).

---

## Step 1 — Verify locally or on staging

```bash
cd backend
.venv/bin/python scripts/purge_soft_deleted_messages.py
```

Expected output when nothing is eligible:

```text
=== Soft-deleted message purge (DRY-RUN) ===
Retention window:  90 days
Cutoff (UTC):      ...
Eligible:          0
Purged:            0
```

If `Eligible` > 0, review the sample message ids, then test apply on staging first:

```bash
.venv/bin/python scripts/purge_soft_deleted_messages.py --apply
```

---

## Step 2 — Choose how to schedule

### Option A — Render cron job (recommended for LC Connect)

LC Connect’s API is on **Render**. Add a **Cron Job** service in the same repo.

1. Open [Render Dashboard](https://dashboard.render.com) → **New** → **Cron Job**.
2. Connect the `LC-CONNECT` repo, branch `main`.
3. Settings:

| Field | Value |
|-------|--------|
| **Name** | `lc-connect-message-purge` |
| **Root directory** | `backend` |
| **Schedule** | `0 4 * * *` (daily 04:00 UTC — adjust for your timezone) |
| **Build command** | `pip install --upgrade pip && pip install -r requirements.txt` |
| **Command** | `PYTHONPATH=. python scripts/purge_soft_deleted_messages.py --apply` |

4. **Environment** — copy from `lc-connect-api` (at minimum `DATABASE_URL`). Optionally set:
   - `MESSAGE_SOFT_DELETE_RETENTION_DAYS=90`
   - `ENVIRONMENT=production`

5. Create the job. After the first run, open **Logs** and confirm `Purged: N` (or `0` if none eligible).

**Optional:** add the cron service to `render.yaml` at the repo root so it’s version-controlled:

```yaml
  - type: cron
    name: lc-connect-message-purge
    env: python
    region: oregon
    schedule: "0 4 * * *"
    branch: main
    rootDir: backend
    buildCommand: |
      pip install --upgrade pip
      pip install -r requirements.txt
    startCommand: PYTHONPATH=. python scripts/purge_soft_deleted_messages.py --apply
    envVars:
      - key: PYTHON_VERSION
        value: "3.12.0"
      - key: ENVIRONMENT
        value: production
      - key: DATABASE_URL
        sync: false
      - key: MESSAGE_SOFT_DELETE_RETENTION_DAYS
        value: "90"
```

Deploy via git push; Render creates/updates the cron service from the blueprint.

---

### Option B — GitHub Actions (no Render cron)

Useful if you prefer CI-scheduled ops or don’t have Render cron on your plan.

Create `.github/workflows/message-retention-purge.yml`:

```yaml
name: Message retention purge

on:
  schedule:
    - cron: '0 4 * * *'   # daily 04:00 UTC
  workflow_dispatch:       # manual run from Actions tab

jobs:
  purge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - name: Install deps
        working-directory: backend
        run: pip install -r requirements.txt
      - name: Purge soft-deleted messages
        working-directory: backend
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          MESSAGE_SOFT_DELETE_RETENTION_DAYS: '90'
        run: PYTHONPATH=. python scripts/purge_soft_deleted_messages.py --apply
```

Add `DATABASE_URL` as a GitHub repository secret (same transaction-pooler URL as production).

---

### Option C — Server crontab (VPS / self-hosted)

On the machine that can reach Postgres:

```cron
# /etc/cron.d/lc-connect-message-purge
0 4 * * * deploy cd /path/to/LC-CONNECT/backend && .venv/bin/python scripts/purge_soft_deleted_messages.py --apply >> /var/log/lc-connect-purge.log 2>&1
```

Ensure `.env` or exported env includes `DATABASE_URL`.

---

## Step 3 — Monitor

After each run, check:

- **Exit code 0** — script completed (even when `Purged: 0`)
- **Log line** `Purged: N` — rows hard-deleted that run
- **No spike in errors** on the main API (purge is independent of request traffic)

If purge fails (DB unreachable, bad URL), fix env and re-run manually:

```bash
PYTHONPATH=. python scripts/purge_soft_deleted_messages.py --apply
```

---

## Safety rules (do not change without policy review)

1. **Report snapshots stay forever** — `reports.message_body` is never deleted by this job.
2. **Only soft-deleted rows** — messages with `deleted_at IS NULL` are never touched.
3. **Retention window** — only rows with `deleted_at` older than the cutoff are eligible.
4. **Dry-run first** after changing `--days` or env on production.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ModuleNotFoundError: No module named 'app'` | Prefix command with `PYTHONPATH=.` (see deployment doc) |
| DB connection timeout | Use Supabase **transaction pooler** URL port **6543** |
| `Eligible: 0` always | Normal if no messages were soft-deleted 90+ days ago |
| Accidental purge concern | Reports still hold text; increase `MESSAGE_SOFT_DELETE_RETENTION_DAYS` before next run |

---

## Related docs

- [`docs/getting-started/deployment.md`](../docs/getting-started/deployment.md) — Render API setup
- [`AUTH_USER_LINKING_RUNBOOK.md`](./AUTH_USER_LINKING_RUNBOOK.md) — similar ops script pattern
