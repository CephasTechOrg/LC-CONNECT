# Groups — Implementation Phases (living plan)

Update the checkboxes as work lands. Architecture + rationale:
[`architecture.md`](./architecture.md).

**Rule for every phase:** it ships only when its **test gate** is green, plus the standard
repo gate (`pytest`, `ruff`, `flutter analyze`, `check_line_limits.py`).

**Ownership while this runs:** P1–P5 are **backend-only** (Claude). The mobile group UI is
built in parallel (Cephas). We converge at P6.

---

## P0 — Contracts + the test harness ✅ **COMPLETE**

The riskiest thing in this plan is moving the message container. Our suite is DB-free, so it
**cannot prove messaging parity on real rows**. P0 built that proof *before* anything moves.

- [x] Group API contract drafted → [`api_contract.md`](./api_contract.md)
- [x] First vertical slice defined (see P4)
- [x] **Postgres integration-test harness** — `backend/tests/db/conftest.py`
  - separate `lc_connect_test` DB, **auto-created**; dev DB never touched
  - schema via `Base.metadata.create_all`; **TRUNCATE per test** (survives service-level `commit()`)
  - **skips cleanly** when Postgres is unreachable → CI without a DB stays green
  - `factory` fixture builds users/profiles/matches/messages/blocks; messages take an explicit
    `created_at` because Postgres `now()` is the *transaction* timestamp
- [x] **13 DM parity tests** against the CURRENT match-based system —
  `backend/tests/db/test_dm_parity.py`:
  - [x] message ordering (real rows)
  - [x] thread-list ordering (`list_threads`)
  - [x] keyset pagination — no gaps/duplicates across pages
  - [x] reconnect sync (`sync_thread`)
  - [x] unread counts (only the partner's unread)
  - [x] read state (`mark_read`) — *was completely untested*
  - [x] duplicate DM prevention (normalized pair, order-independent)
  - [x] send idempotency (real partial unique index)
  - [x] unauthorized conversation access (non-member, unknown, blocked)

**Gate: ✅ green** — 103 backend tests pass, ruff clean, line limits pass, dev data intact.

### Running the DB tests
```bash
cd backend && .venv/bin/pytest tests/db/        # auto-creates lc_connect_test
TEST_DATABASE_URL=... .venv/bin/pytest tests/db/   # point at another Postgres
```
They skip (not fail) if Postgres isn't running.

> **These 13 tests are the contract for P2.** After the migration they must pass *unchanged*
> against the conversation-based path. That is the definition of parity.

---

## P1 — Conversation foundation ✅ **COMPLETE** *(additive; nothing reads it yet)*

- [x] `Conversation` + `ConversationMember` models (`app/models.py`)
  - `Conversation.match_id` is **UNIQUE** → a match can never have two conversations, so
    duplicate DMs remain structurally impossible (inherits `uq_match_pair`)
  - `ConversationMember` carries `role`, `status`, `invited_by`, `muted`, `joined_at`, and
    `last_read_message_id` (column added now; *used* in P2)
- [x] `Message.conversation_id` **nullable**; `match_id` **retained**
- [x] Migration `e5f6a7b8c9d0_add_conversations.py` (tables + column + backfill)
- [x] Backfill SQL extracted to `app/shared/conversation_backfill.py` so the **migration and
      tests run the identical statements**; every statement is idempotent
- [x] No service reads `conversation_id` — pure data addition

**Gate: ✅ green**
- 6 backfill tests + **the 13 parity tests still pass unchanged** → behaviour provably intact
- 109 backend tests · ruff clean · **OpenAPI snapshot unchanged** · line limits pass
- **Verified on the real dev database:** 1 match → 1 conversation, 2 members, **53/53 messages
  linked, 0 unlinked, 0 mismatched**, `match_id` still set on all 53
- **Rollback proven end-to-end:** `alembic downgrade -1` → tables/column gone, all 53 messages
  intact; `alembic upgrade head` → fully re-backfilled (53/53)

---

## P2 — Cut messaging over to `conversation_id` + per-member read boundary

The heaviest phase. Dual-write `match_id` throughout so rollback stays trivial.

- [ ] Messages service/router read `conversation_id`
- [ ] Realtime `authorize_conversation` → `ConversationMember` lookup
- [ ] Push + unread read conversations
- [ ] **Introduce `ConversationMember.last_read_message_id`**; migrate unread off per-message `read_at` (see architecture D3)
- [ ] Keep writing `match_id` (rollback safety)

**Gate:** the **P0 parity tests pass identically** against the new path · snapshot unchanged for
DM endpoints · mobile untouched and still green.

---

## P3 — `Group` entity, membership & join flows

- [ ] `Group` table + its `Conversation(kind='group')`
- [ ] `ConversationMember.role` (`owner|admin|member`) + `status` (`invited|requested|active|removed|banned`)
- [ ] Endpoints: create · my groups · get group · update · leave · remove/ban · promote/transfer
- [ ] Join flows: **open** · **approval-required** (request → admin approves) · **direct admin invite**
- [ ] **Transactional capacity** for `max_members` (must not copy Activities' naive count)
- [ ] Group policy module (centralized permissions + invariants: always an owner; transfer before leaving; admin can't remove owner; banned can't rejoin)

**Gate:** permission/invariant tests · **concurrent-join capacity race test** · join-flow tests
(open/approval/invite) · unauthorized-action tests.

---

## P4 — Group messaging + realtime fan-out

Group chat largely *falls out* of P2. What's new is fan-out.

- [ ] Broadcast to **all** members (not "the partner"); typing to all others
- [ ] **Push fan-out** to all *offline, non-sender, non-muted* members
- [ ] **Revoke-on-removal** (removed/banned member's subscription is closed immediately)
- [ ] Thread-list **group variant** (group title + avatar instead of partner)
- [ ] Group unread via the per-member boundary

**First vertical slice (end-to-end):** create an open group → discover it → join → open its
conversation → send/receive a text message → mark read → leave.

**Gate:** fan-out tests · removal-revocation test · group unread test · sender/muted exclusion
tests.

---

## P5 — Group discovery, profile & moderation

- [ ] Discovery/search respecting `visibility` (`public` listed, `unlisted` link-only, `private` hidden)
- [ ] Group profile + **avatar reusing `sanitize_avatar`**
- [ ] Report targets: nullable `group_id` / `message_id` on `Report`
- [ ] Member remove/ban surfaced to admins

**Gate:** visibility tests (each policy) · report-target tests.

---

## P6 — Mobile wiring *(converge with the parallel UI work)*

- [ ] Wire the existing group UI to the API
- [ ] Group variant in the thread list + group unread badges
- [ ] Group chat screen reuses the existing realtime client

**Gate:** `flutter analyze` · dart tests · on-device check.

---

## Later (explicitly out of scope for now)

- [ ] Shareable invite links (token hashing, expiry, revocation, usage limits, race protection)
- [ ] Media / attachments for DMs **and** groups (private bucket + signed URLs + sanitization)
- [ ] Audit-log table + moderation dashboard
- [ ] Group events / announcements / posts (the `Group` entity is designed to absorb these)
- [ ] Fix Activities' capacity race

---

## Migration & rollback strategy

**Principle: every step is additive and reversible until the final cleanup.**

| Phase | Forward | Rollback |
|---|---|---|
| P1 | Add tables + nullable `conversation_id`; backfill | Drop the new columns/tables — DMs still run on `match_id` |
| P2 | Services read `conversation_id`; `match_id` still written | Revert the service layer to `match_id` (data still intact) |
| P3–P5 | Purely new tables/endpoints | Feature-flag or drop the group endpoints |
| Later | Drop `Message.match_id` **only after** sustained parity | — (point of no return; do last, deliberately) |

**Risk context:** there is **no production data yet** (pre-pilot), so the destructive final
step is cheap. We still stage it — correct practice, and it keeps the rollback story honest.

**Parity check before any destructive step:** diff old (match-based) vs new
(conversation-based) results for threads, ordering, and unread on real rows.
