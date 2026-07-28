# LC Connect Admin

Next.js (App Router) admin portal for Campus Hub. Signs in with the same
**Supabase Auth** project as mobile (email + password + MFA). FastAPI remains
the authorization source of truth (`role=admin` + JWT `aal=aal2`).

## Setup

See **[docs/getting-started/admin_portal.md](../docs/getting-started/admin_portal.md)**
for first-admin promote, MFA, and local run instructions.

```bash
cp .env.local.example .env.local   # fill Supabase + API URL
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Stack

- Next.js App Router + TypeScript
- `@supabase/ssr` / `@supabase/supabase-js` (anon key only)
- Bearer calls to FastAPI `/api/v1/admin/*`

Never put the Supabase service-role key in this app.
