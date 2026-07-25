# Security, Safety & Compliance

The authorization model, encryption posture, abuse prevention, and data-retention policy — the docs a
security reviewer (or a careful developer) should read.

| Doc | What it's for |
|-----|---------------|
| [`overview.md`](./overview.md) | **Start here.** Authentication (Supabase JWT), authorization (membership/ownership, why there's no IDOR), and the encryption posture (TLS + at-rest, why *not* E2EE) |
| [`rate_limiting.md`](./rate_limiting.md) | Login limits (Supabase) vs per-user abuse limits, the numbers, the `RATE_LIMIT_*` env vars, and the 429 UX |
| [`rls_messages.md`](./rls_messages.md) | Supabase Row-Level Security on the messages table (defense-in-depth for direct DB access) |
| [`audit_and_data_retention.md`](./audit_and_data_retention.md) | What's soft-deleted vs permanently deleted, report evidence snapshots, and the moderator playbook |
