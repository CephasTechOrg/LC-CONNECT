# Security, Safety & Compliance

The authorization model, encryption posture, abuse prevention, and data-retention policy — the docs a
security reviewer (or a careful developer) should read.

| Doc | What it's for |
|-----|---------------|
| [`overview.md`](./overview.md) | **Start here.** Supabase Auth JWT, FastAPI authz (no IDOR), FastAPI WebSockets, encryption posture (why *not* E2EE) |
| [`rate_limiting.md`](./rate_limiting.md) | Login limits (Supabase) vs per-user abuse limits (`aallow` / Redis), env vars, 429 UX |
| [`rls_messages.md`](./rls_messages.md) | Supabase RLS on messages — defense-in-depth (chat delivery is FastAPI WS) |
| [`audit_and_data_retention.md`](./audit_and_data_retention.md) | Soft vs hard delete, report evidence, export, moderator playbook |
| [`../../architecture_review/MESSAGE_RETENTION_CRON_RUNBOOK.md`](../../architecture_review/MESSAGE_RETENTION_CRON_RUNBOOK.md) | **Daily cron setup** for soft-deleted message purge (#21) |
