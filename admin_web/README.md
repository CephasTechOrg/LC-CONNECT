# LC Connect Admin Web (legacy)

**Prefer the Next.js app in [`admin/`](../admin/)** (Supabase login + MFA, no token paste).
See [`docs/getting-started/admin_portal.md`](../docs/getting-started/admin_portal.md).

This folder is a temporary static tool for reviewing campus position submissions.

## What it does

- Lists pending campus positions from `GET /api/v1/admin/campus-positions/pending`
- Approve via `POST /api/v1/admin/campus-positions/{id}/approve`
- Reject via `POST /api/v1/admin/campus-positions/{id}/reject`

## Requirements

- An LC Connect account with `role=admin`
- Supabase MFA enabled (`aal2`) — admin API routes use `require_admin_aal2`
- A current Supabase **access token** for that admin user

## Run locally

From the repo root:

```bash
cd admin_web
python3 -m http.server 5174
```

Open [http://localhost:5174](http://localhost:5174), set:

- **API base URL:** `http://localhost:8000/api/v1`
- **Bearer token:** paste a fresh admin access token

Then click **Refresh**.

## Notes

- This is intentionally small — no build step, no framework.
- Tokens are stored only in `localStorage` on your machine for convenience during local review.
- Revoke verified positions is API-only for now (`POST .../revoke`).
