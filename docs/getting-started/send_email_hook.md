# Supabase "Send Email" Auth Hook — setup

## What this is and why it exists

LC Connect sends its own branded email for every Supabase auth action (signup confirmation,
password recovery, admin/employer invites) instead of Supabase's own dashboard-configured
templates. Two different mechanisms cover this, because two different kinds of calls trigger
Supabase auth emails:

1. **Backend-triggered** (admin invites, employer approval/resend, admin/employer forgot-password)
   — the backend itself calls `admin.generate_link(...)`, which returns the link/code **without**
   Supabase sending anything, and the backend emails it directly
   (`app/shared/supabase_admin.py`). No hook needed for these — already live.
2. **Mobile-app-triggered** (`supabase.auth.signUp()`, `resend()`, `resetPasswordForEmail()`) —
   these calls go **straight from the Flutter app to Supabase**, never touching this backend at
   all. The only way to override their emails is at the Supabase *project* level: the "Send
   Email" Auth Hook. Once enabled, Supabase calls **our** webhook instead of sending anything
   itself, for every auth email, from every client — covering mobile with zero mobile code
   changes.

This doc is only for **#2** — the piece that needs manual Supabase Dashboard configuration I
can't do from the codebase.

---

## Setup steps

### 1. Deploy/expose the webhook endpoint

Supabase needs to be able to reach:

```
POST https://<your-backend-host>/api/v1/auth/webhooks/send-email
```

- **Production (Render)**: this is already reachable once the backend is deployed —
  `https://lc-connect-api.onrender.com/api/v1/auth/webhooks/send-email` (see
  `docs/getting-started/deployment.md`).
- **Local development**: Supabase Cloud cannot reach `localhost` directly. Use a tunnel
  (e.g. `ngrok http 8000`) and use the tunnel's HTTPS URL instead, or skip local testing of this
  specific hook and rely on the production backend.

### 2. Enable the hook in the Supabase Dashboard

Dashboard → **Authentication** → **Hooks** → **Send Email**:

1. Toggle it on.
2. Hook type: **HTTPS**.
3. URL: the endpoint from step 1.
4. Supabase generates a signing secret (starts with `whsec_`) — copy it.

### 3. Set the secret

Add the copied secret to the backend's environment:

```env
SUPABASE_SEND_EMAIL_HOOK_SECRET=whsec_...
```

- Local: `backend/.env`
- Production: Render Dashboard → `lc-connect-api` → Environment → add
  `SUPABASE_SEND_EMAIL_HOOK_SECRET` (mark it secret, `sync: false` in `render.yaml`).

Until this is set, the endpoint returns `503` for every request — it never processes an
unverifiable webhook rather than silently trusting an unsigned one.

### 4. Confirm which email types are covered

The hook fires for every Supabase auth email once enabled: signup confirmation, magic link,
recovery (password reset), invite, and email-change. LC Connect's handler
(`app/features/auth/email_hook.py`) maps each to a branded template:

| Supabase `email_action_type` | LC Connect template |
|---|---|
| `recovery` | `send_password_reset_email` |
| `invite` | `send_invite_email` |
| everything else (`signup`, `magiclink`, `email_change`, ...) | `send_signup_confirmation_email` |

---

## Verifying it worked

1. Sign up a brand-new test account in the mobile app.
2. Check the inbox — it should arrive from your configured Resend sender
   (`RESEND_FROM_EMAIL`), with LC Connect's own "Welcome to LC Connect! Confirm your email
   address" wording — **not** Supabase's generic "Confirm your email" template.
3. Try mobile's forgot-password flow — same check, should say "Reset your LC Connect password."
4. If either still shows Supabase's own generic wording, double check: the hook is toggled on,
   the URL is correct and reachable, and `SUPABASE_SEND_EMAIL_HOOK_SECRET` matches what's in the
   Dashboard exactly (including the `whsec_` prefix).

## If something goes wrong

Because the hook is required for the underlying Supabase action to complete (Supabase blocks
signup/recovery/etc. if the hook call fails), a misconfigured hook can make signup or password
reset **fail entirely** for real users — not just silently skip the custom email. If you need to
roll back quickly: Dashboard → Authentication → Hooks → Send Email → toggle off. Supabase
immediately reverts to sending its own default emails, and nothing else about auth changes.
