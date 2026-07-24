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

## P2 — Cut messaging over to `conversation_id` + per-member read boundary ✅ **COMPLETE**

The heaviest phase. `match_id` is **dual-written** throughout so rollback stays trivial.

- [x] New shared layer `app/shared/conversations.py` — `ensure_dm_conversation` (idempotent
      get-or-create), `active_member_ids`, `is_active_member`, `match_ids_for_conversations`
- [x] Messages service reads `conversation_id` (`page_thread` / `sync_thread` / write path
      dual-writes both ids); router **translates match_id ↔ conversation_id at the edge** so
      the public API is byte-identical
- [x] Realtime `authorize_conversation` → **membership lookup** (`ConversationMember`); returns
      a `Conversation`; DM block rule preserved
- [x] Gateway send/subscribe use **active members** (partner for a DM, fan-out audience for a
      group) — push already loops over recipients
- [x] New matches provision their conversation at creation (`connections/router.py`)
- [x] **Unread moved to `last_read_message_id`** (`ConversationMember`); `read_at` retained for
      DM receipts. `mark_read` advances the boundary (forward-only) + stamps `read_at`
- [x] **Read-state parity migration** `f6a7b8c9d0e1` — seeds the boundary from existing
      `read_at` so already-read messages don't resurface

**Gate: ✅ green**
- **All 13 P0 parity tests pass unchanged against the conversation path** ← the core proof
- 6 backfill tests (incl. read-boundary parity) · 106 backend tests · ruff clean
- **OpenAPI snapshot + route inventory unchanged** → mobile untouched and safe
- Obsolete mock tests retired (`test_realtime_service.py` — its logic moved to `tests/db/`)
- **Verified on real dev data (53 messages):** `page_thread` returns them via the conversation
  path; after the read-boundary migration, boundary-unread **equals** the old `read_at`-unread
  (0=0 for both members)

### The transition invariant (still true after P2)
Every message has **both** `match_id` and `conversation_id`; the public API still speaks
`match_id`. So rollback is still just reverting the service layer — the external flip to
`conversation_id` happens later (P4/P6), with groups.

### P1/P2 hardening pass ✅
Reviewed the foundation before P3 and closed the gaps:
- **Race safety** — `ensure_dm_conversation` now catches the `IntegrityError` from the UNIQUE
  `match_id` and reloads the winner (two concurrent creators can't duplicate a conversation).
- **Indexing** — added `ix_messages_conversation_created_id (conversation_id, created_at DESC,
  id DESC)` (migration `a7b8c9d0e1f2`), the conversation-keyed equivalent of the old match
  keyset index; serves paging, sync, and the unread boundary scan. Legacy match indexes kept
  for rollback.
- **Cleanup** — removed dead `outerjoin`/`aliased` from `mark_read`; fixed the stale
  "(match_id, …)" service docstring.
- **New edge-case tests** (`tests/db/test_conversation_hardening.py`): `mark_read` boundary is
  **forward-only** (out-of-order reads can't un-read), `ensure_dm_conversation` idempotent (no
  duplicate conversation/members), new matches provisioned with a conversation.

**Gate: ✅** 109 backend tests · ruff clean · single alembic head (`a7b8c9d0e1f2`) · app boots ·
line limits pass.

---

## P3 — `Group` entity, membership & join flows ✅ **COMPLETE**

New feature module `app/features/groups/` (router/service/schema/policies) + `Group` model.

- [x] `Group` table (migration `b8c9d0e1f2a3`) owning a `Conversation(kind='group')`; membership
      reuses `ConversationMember` (`role` owner|admin|member, `status`
      invited|requested|active|removed|banned)
- [x] Endpoints: create · my groups · discover · get (visibility-gated) · members · requests ·
      approve · reject · invite · accept-invite · leave
- [x] Join flows: **open** (instant) · **approval** (request → admin approves) · **invite**
      (admin invite → accept); banned users rejected
- [x] **Transactional capacity** — `SELECT … FOR UPDATE` on the group row serializes concurrent
      joins (`service._reserve_capacity`); enforced at join *and* approve
- [x] Centralized **policy module** (`policies.py`) — action→min-role matrix, `can_moderate`
      (strict-outrank), owner-only actions never granted to admins; owner-must-transfer-before-leaving
- [x] OpenAPI snapshot regenerated for the new `/groups` routes

**Gate: ✅ green**
- **Real concurrent-join race test** (`test_capacity_is_race_safe_under_concurrent_joins`) — two
  sessions contend for a 1-slot group; exactly one wins, final active count is never exceeded
- 12 group integration tests (create/open/approval/invite/banned/capacity/visibility/leave) +
  6 policy unit tests
- 126 backend tests · ruff clean · single alembic head · line limits pass

### Deferred to a follow-up (P3b / P5 moderation) — noted, not built
`PATCH /groups/{id}` (edit) · avatar upload (reuses `sanitize_avatar`) · remove/ban a member ·
promote/demote admin · transfer ownership · delete group. The `policies.py` matrix already
covers these actions; only the routes/service wiring remain.

---

## P4 — Group messaging + realtime fan-out ✅ **COMPLETE**

Group chat mostly fell out of P2. What P4 added:

- [x] **Address by conversation id** — `resolve_conversation` accepts a group's conversation id
      *or* a DM's match id, so the same gateway path serves both. `authorize_conversation` +
      `mark_read` use it.
- [x] `messages.match_id` **made nullable** (migration `c9d0e1f2a3b4`) — group messages have only
      a `conversation_id`; DM messages still carry both.
- [x] Broadcast to **all** members; **typing fans out to every other member** (`conn.partners`
      is now a list, cached at subscribe)
- [x] **Push fan-out** to all *offline, non-sender, non-muted* members
      (`active_members_with_mute`)
- [x] **Revoke-on-removal** — `manager.revoke_member` closes a removed/banned member's
      subscription; wired into `DELETE /groups/{id}/members/{user_id}?ban=`
- [x] Group unread via the per-member boundary (already conversation-keyed from P2)

**Gate: ✅ green**
- 6 group-messaging integration tests (send-by-conversation-id · non-member rejected · fan-out ·
  muted-flagged · per-member unread boundary · removed-member-loses-access)
- Realtime gateway/manager tests updated for the member-list + muted fan-out
- 132 backend tests · ruff clean · snapshot regenerated (new remove-member route) · single head
- **Verified on dev DB:** created a group, member joined, sent a message addressed by
  conversation id, owner's group unread = 1 — then cleaned up

### Deferred (breaking mobile change → lands in P6 with the UI)
Thread-list **group variant** + surfacing group unread through `/messages/*` (the router still
translates to `match_id` and drops groups). That's the coordinated `match_id`→`conversation_id`
API flip, done with the mobile wiring.

### Fixed during P4
A stray file rename had turned `groups/service.py` into a file literally named `.py`, which
surfaced as a fake "circular import". Restored + made the groups package import-order-robust.

---

## P5 — Group admin surface, profile & moderation ✅ **COMPLETE**

- [x] Discovery/search respecting `visibility` (done in P3: `public` listed, `unlisted`/`private`
      never listed; get-by-id gated)
- [x] **Group avatar** — `POST /groups/{id}/avatar` reuses `sanitize_avatar` (EXIF/GPS stripped)
      via a generalized `storage._upload_avatar` + `upload_group_image`
- [x] **Edit group** — `PATCH /groups/{id}` (admin/owner)
- [x] **Role management** — `PATCH /groups/{id}/members/{user_id}` (promote/demote, `can_moderate`
      enforced) · **`POST /groups/{id}/transfer`** (owner-only; old owner steps down to admin so
      there is always exactly one owner) · **`DELETE /groups/{id}`** (owner-only; deletes the
      conversation → cascades to group + members + messages)
- [x] **Report targets** — nullable `group_id` / `message_id` on `Report` (migration
      `d0e1f2a3b4c5`); safety schema + service accept them; a target is required
- [x] Member remove/ban shipped in P4

**Gate: ✅ green**
- 8 admin tests: edit · promote · **transfer keeps exactly one owner** · admin-can't-moderate-admin ·
  **delete cascade** (group+members+messages gone) · report a group · report a message · target-required
- 140 backend tests · ruff clean · snapshot regenerated · single head `d0e1f2a3b4c5` · line limits

**The group backend is now feature-complete for the MVP.** Remaining: **P6 — wire the mobile UI**
(the coordinated `match_id`→`conversation_id` API flip + group thread-list variant + group unread).

---

## P6 — Mobile wiring ✅ **COMPLETE** *(remaining polish moved to P7)*

**Stage A ✅ — groups discovery / join / create**
- [x] Mobile data layer: `groups/data/group_models.dart` (`GroupSummary`/`GroupRead`),
      `groups/providers/groups_provider.dart` (repository + `discoverGroupsProvider`/`myGroupsProvider`)
- [x] `groups_panel.dart` rewired to `GET /groups/discover` (was static placeholder), preserving
      the tile/button visuals; category chips map to backend categories
- [x] Join/Request → `POST /groups/{id}/join`; **Create Group** sheet → `POST /groups`

**Stage B ✅ — group chat**
- [x] **Backend (non-breaking):** message endpoints (`GET/POST /messages/threads/{id}` + `/sync`)
      now resolve the path id as a match id *or* a group conversation id via
      `accessible_conversation` — DMs byte-identical (parity tests + **snapshot unchanged**),
      groups now message through the same endpoints + the same WebSocket
- [x] `Message.match_id` nullable (P4) lets group messages persist
- [x] Mobile: tapping a group you're a member of fetches its `conversation_id` and opens
      `ChatScreen` in **group mode** (`groupTitle` → group-name header, no partner card);
      reuses the whole realtime/send/unread engine. Route `'/messages/group/:conversationId'`.

**Gate: ✅ green** — 142 backend tests · 120 mobile tests · analyze clean · line limits pass.
Group chat **verified working on-device** (send/receive between two accounts).

**Two bugs found + fixed during on-device testing** (both now covered by tests):
1. Realtime frames tagged `conversation_id` with `str(message.match_id)` → `"None"` for group
   messages, so the client couldn't route them. Fixed with `protocol.addressing_id` (match id
   for DMs, conversation id for groups). DM frames byte-identical.
2. `MessageRead.match_id` was a required `UUID`, but group messages have `match_id=None` → the
   history endpoint 500'd. Made it nullable + added `conversation_id` to the DTO. *(This is why
   groups showed a notification banner but no messages when opened.)*

---

## P7 — Groups in the Messages inbox + polish 🟡 **IN PROGRESS**

**Slice 1 ✅ — unified Messages inbox (DM + group threads)**
- [x] **Backend:** `list_threads_for_user` returns DM *and* group threads, newest-activity-first;
      `MessageThreadRead` carries `conversation_id` + `kind` + nullable `match_id`, a `partner`
      (DM) or a `group` (`GroupThreadInfo{id,name,avatar_url}`). `/messages/unread-summary` now
      keys by the client addressing id via `addressing_ids_for_conversations` (groups included,
      no longer dropped).
- [x] **Mobile:** `MessageThread` gains `conversationId`/`kind`/nullable `matchId`/group fields
      with `isGroup`, `addressingId` (= `matchId ?? conversationId`), `title`, `avatarUrl`;
      `_ThreadCard` renders group rows (group name/avatar) and taps route to
      `/messages/group/{conversationId}` for groups vs `/messages/{matchId}` for DMs; live
      `conversation.updated` + typing match by `addressingId`, so group previews/unread update
      in the list.

**Gate: ✅ green** — 143 backend tests · 120 mobile tests · analyze clean · line limits pass ·
snapshot regenerated for the additive thread/unread payload.

**Still open (P7 Slice 2/3):**
- [ ] Group detail / admin screen (members list, approve/reject requests, invite, promote/transfer,
      edit, avatar upload, remove/ban, delete) wired to the endpoints
- [ ] Per-sender name/avatar on group message bubbles (DM-style bubbles for now) + report actions

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
