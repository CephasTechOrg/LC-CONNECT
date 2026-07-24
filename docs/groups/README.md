# Groups — Campus Communities

Design + implementation reference for LC Connect **groups** (clubs, housing, classes,
interest groups) and the messaging generalization they require.

| Doc | What it's for |
|-----|---------------|
| [`groups_reference.md`](./groups_reference.md) | **The behavior & policy reference.** How groups work *today* — roles, permissions, join flows, messaging, notifications, moderation, limits, every endpoint. Start here if you want to know what the system *does*. |
| [`architecture.md`](./architecture.md) | The final architecture, every design decision and *why*, what we deliberately deferred, and the impact map on existing systems. |
| [`api_contract.md`](./api_contract.md) | The **endpoints + payloads** the mobile group UI is built against. |
| [`implementation_phases.md`](./implementation_phases.md) | The **living build log**: phases + follow-ups with deliverables, test gates, and checkboxes. |
| [`../audit_and_data_retention.md`](../audit_and_data_retention.md) | App-wide **audit & data-retention policy**: what's soft-deleted vs hard-deleted, evidence snapshots, and the moderator playbook. |

---

## Status

**P0–P5 ✅ complete — the group backend is feature-complete. Next: P6 (wire the mobile UI).**

Groups now **chat**: a group is addressed by its conversation id, messages fan out to all
members (typing too), push skips muted members, and removing a member closes their live socket.
Verified end-to-end on the dev DB. The one thing still on `match_id` externally — the thread
list + unread surfacing — is the coordinated breaking change that lands with the mobile UI (P6).

Groups are real: `POST /groups`, discover, join (open/approval/invite), approve/reject, invite,
leave — with **transactionally race-safe capacity** and a centralized permission matrix. A group
is a `Conversation(kind='group')` owned by a `Group` domain entity. Because P2 already made
messaging membership-based, **group chat mostly falls out in P4** (it just needs fan-out + a
thread-list variant).

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
