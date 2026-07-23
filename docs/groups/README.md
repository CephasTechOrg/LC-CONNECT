# Groups — Campus Communities

Design + implementation reference for LC Connect **groups** (clubs, housing, classes,
interest groups) and the messaging generalization they require.

| Doc | What it's for |
|-----|---------------|
| [`architecture.md`](./architecture.md) | **Start here.** The final architecture, every design decision and *why*, what we deliberately deferred, and the impact map on existing systems. |
| [`api_contract.md`](./api_contract.md) | The **endpoints + payloads** the mobile group UI is built against (draft until reconciled with the real screens). |
| [`implementation_phases.md`](./implementation_phases.md) | The **living plan**: phases P0–P6 with deliverables, test gates, and checkboxes. Update as we go. |

---

## Status

**P0 ✅ · P1 ✅ · P2 ✅ complete — next up: P3 (the `Group` entity + join flows).**

Messaging now runs on `conversation_id` internally (authorization is membership-based, unread
uses the per-member `last_read_message_id` boundary), while the **public API and mobile app are
completely unchanged** — the router translates at the edge. All 13 parity tests pass against the
new path; verified on the real dev DB. Groups now largely *fall out* of this: a group is just a
conversation with N members.

The safety net exists: a Postgres integration harness (`backend/tests/db/`) plus **13 DM
parity tests** that lock in today's messaging behaviour (ordering, pagination, sync, unread,
read state, idempotency, duplicate-DM prevention, authorization). Those tests must pass
*unchanged* after the migration — that's how we prove nothing broke.

The `Conversation` / `ConversationMember` tables now exist and every existing DM + message is
backfilled onto them (verified on the real dev DB: 53/53 messages linked). **Nothing reads
them yet** — `match_id` is still the live path, so rollback is a single `alembic downgrade`
(proven end-to-end).

```bash
cd backend && .venv/bin/pytest tests/db/     # auto-creates lc_connect_test; skips if no Postgres
```

The core change: messaging today is hard-wired to 1:1 (`Message.match_id` → a two-person
`Match`). Groups require generalizing that container to a **`Conversation`**, and adding a
**`Group`** domain entity that owns its conversation.

## The one hard prerequisite

Our backend test suite is intentionally **DB-free** (mocks + SQL-shape + OpenAPI snapshot).
That proves the API contract and isolated logic, but **not** that messaging still behaves
correctly on real rows. Because P1/P2 move the message container, **P0 must first build a
Postgres integration-test harness and DM parity tests**. Those tests are the safety net that
makes the rest of the plan safe.

## Parallel work (who owns what)

Phases **P1–P5 are backend-only**. The mobile group UI is being built in parallel by Cephas,
so during those phases:

- **Claude → backend** (`backend/**`) + these docs.
- **Cephas → mobile** (`mobile/lib/features/groups/**`, UI polish).

We converge at **P6 (mobile wiring)**, where the existing group UI is connected to the API.
