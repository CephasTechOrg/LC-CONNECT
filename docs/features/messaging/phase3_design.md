# Phase 3 — Messaging: design before implementation

Companion to [`docs/reviews/BETA_FEEDBACK_REVIEW.md`](../../reviews/BETA_FEEDBACK_REVIEW.md) Part 4b,
items 3.1–3.8. The review says *what* to build; this settles *how*, and fixes the order.

Phase 3 covers seven beta reports: #2 (nav bar in conversations), #19 (groups hard to find),
#1 (drafts lost), #21 (sending/delivery/read states), #23 (read receipts invisible), #4 (reactions),
#5 (editing).

---

## 0. Two prerequisites the review missed

Both surfaced while checking assumptions. Neither is optional, and both are cheap.

### 0a. An unknown frame type currently gets the socket banned

`protocol.parse_inbound` is a Pydantic discriminated union on `type`
([protocol.py:108-112](../../../backend/app/features/realtime/protocol.py#L108-L112)). A frame with an
unrecognised `type` raises `ValidationError`, which the gateway routes to `_tolerate_malformed`
([gateway.py:130-135](../../../backend/app/features/realtime/gateway.py#L130-L135)) — and that shares the
**abuse budget** of 10 per 60 s. On the eleventh, the connection is closed with `4429`.

`4429` is not in the client's do-not-retry set — only `4403` is
([realtime_client.dart:38](../../../mobile/lib/core/realtime/realtime_client.dart#L38)) — so the client
reconnects, sends the same unsupported frame, and gets banned again. **A reconnect loop.**

Every remaining item in this phase adds a frame type, so a client that ships ahead of the server (or
a user who declines an app update) would hit exactly this.

**Fix, in this order:**

1. **Server: distinguish "unsupported" from "malformed."** A well-formed JSON frame with an
   unrecognised `type` is a *version mismatch*, not abuse. It gets a soft
   `error{code: 'unsupported_frame'}` and does **not** touch the abuse budget. Malformed stays what
   it should mean: unparseable JSON, or a known type with invalid fields.
2. **Client: keep the negotiated version.** `auth.ok` already carries `protocol_version` and the
   client already parses it into `AuthOk` — and then **discards it**
   ([realtime_client.dart:161](../../../mobile/lib/core/realtime/realtime_client.dart#L161)). Retain it,
   expose it, and gate every new frame send on it.
3. **Bump `PROTOCOL_VERSION` to 2 once**, with the first new frame — not once per feature.

(1) protects clients already in the wild, which is why it must land first. (2) stops the client
wasting frames it knows the server cannot read. Deploy order for the whole phase is therefore
**server before client, always** — the same ordering that worked for Phases 0–2.

### 0b. The message cache has no format version

`chat_message_cache.dart` writes a bare JSON array with hand-rolled field mapping
([:55-82](../../../mobile/lib/features/messages/data/chat_message_cache.dart#L55-L82)). Three items below
add fields to `ChatMessage` (`editedAt`, `reactions`, delivery state). Missing keys read as `null`
today, so *additive* change is survivable — but there is no way to ever make a breaking one, and no
way to tell a v1 file from a v3 file.

**Fix:** wrap in an envelope before anything starts writing new fields.

```jsonc
{ "v": 1, "messages": [ … ] }
```

A bare array is read as v0. An unknown future `v` is discarded rather than mis-parsed — the cache is
a convenience, so dropping it is always safe, and a mis-parse is not.

---

## 1. Sequencing: friction before features

The seven reports are not the same kind of thing:

| | reports | nature |
|---|---|---|
| **Friction** — things that are wrong | #2, #19, #1, #21, #23 | users hit these and complain |
| **Features** — things that are absent | #4, #5 | users asked for these |

The friction batch is smaller, carries no schema risk beyond one nullable column, and fixes
complaints already on record. **Ship 3.0–3.5 to TestFlight, gather feedback, then build 3.6–3.7.**
Reactions and editing are the two largest items in the phase and the only two that add tables; there
is no reason for the friction fixes to wait behind them.

Within that:

```
3.0  protocol + cache prerequisites        (unblocks everything)
3.1  chat out of the shell  ─┐
3.2  Messages hub (Chats|Groups) ─┘ one change — both rewrite the route table
3.3  drafts                            (depends on 3.1's canonical ids)
3.4  delivery boundary  ─┐
3.5  tick + row state    ─┘ 3.5 renders what 3.4 produces
────────── ship, then ──────────
3.6  reactions
3.7  editing                           (shares 3.6's frame plumbing)
3.8  record the no-presence decision   (doc only)
```

**3.1 and 3.2 are one change, not two.** Both rewrite the route table; doing them separately means
touching it twice and testing the navigation surface twice.

---

## 2. Data structures

### 2.1 Delivery — a per-member boundary, not a per-message flag

```sql
ALTER TABLE conversation_members
  ADD COLUMN last_delivered_message_id UUID NULL
  REFERENCES messages(id) ON DELETE SET NULL;
```

One nullable column, mirroring `last_read_message_id`
([messaging.py:50-52](../../../backend/app/models/messaging.py#L50-L52)).

**Why not `messages.delivered_at`.** A single column cannot express "who has it" in an N-member
conversation — the exact reason `last_read_message_id` exists, recorded in that model's own comment.
**Why not a `message_deliveries` table.** At group scale that is `messages × members` rows for a
cosmetic tick. The boundary is O(members).

**Advance monotonically only**, like `mark_read`
([realtime/service.py:87-150](../../../backend/app/features/realtime/service.py#L87-L150)): compare
`(created_at, id)` tuples and never move backwards. That makes an out-of-order ack harmless and the
operation idempotent, which matters because the client will re-send boundaries after a reconnect.

**"Delivered" means the recipient's device has it** — acknowledged by the client, not enqueued by the
server. An enqueue to a half-open socket is not delivery, and the client already detects half-open
sockets for precisely this reason. So: new inbound frame `messages.delivered{conversation_id,
through_message_id}`, symmetric with the existing `messages.read`; new outbound
`messages.delivery{conversation_id, user_id, through_message_id}`, symmetric with `messages.receipt`.

**Scope decision — DMs only in v1.** For a DM there is one partner, so the sender's tick follows
directly from one boundary. For a group, "delivered" needs a rule (all members? any?) *and*
per-member boundaries held on the client to evaluate it. That is real state for a tick nobody
reported wanting. Groups keep ✓ (sent) and get a **"read by" list on long-press** instead, which is
more informative than a tick and needs no client-side aggregation.

### 2.2 Reactions — a table, and one aggregate query per page

```sql
CREATE TABLE message_reactions (
  id          UUID PRIMARY KEY,
  message_id  UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  emoji       VARCHAR(8) NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (message_id, user_id, emoji),          -- makes toggling idempotent
  INDEX (message_id, emoji)                      -- serves the aggregate below
);
```

**Not a JSON column on `messages`.** A blob cannot carry a unique constraint, so two people
reacting at once would lose a write; and toggling would be read-modify-write on a hot row.

**The aggregate must be one query per page, never per message.** With the API in Oregon and the
database in Ohio (~50–70 ms RTT — see review Part 5 item 2), an N+1 over a 50-message page would cost
**three seconds**. One extra round trip is ~60 ms and acceptable:

```sql
SELECT message_id, emoji, count(*) AS n, bool_or(user_id = :me) AS mine
FROM message_reactions
WHERE message_id = ANY(:message_ids)
GROUP BY message_id, emoji;
```

`bool_or(user_id = :me)` gets "did I react" in the same pass rather than a second query.

**Emoji is a short string against a server-side allowlist**, not a free-text column and not an enum
table. The allowlist (6–8 entries, one constant in `messages/service.py`) bounds the aggregate,
prevents abuse via arbitrary payloads, and keeps the column readable in a database console.

*Client:* `ReactionSummary(emoji, count, reactedByMe)`, an immutable list on `ChatMessage`.

*Authorization:* reuse `accessible_conversation`
([conversations.py:134](../../../backend/app/shared/conversations.py#L134)) — it already handles
not-a-member (404), blocked (403), and closed staff thread (403). Reject reactions on soft-deleted
messages.

### 2.3 Editing — `edited_at` plus an audit table

```sql
ALTER TABLE messages ADD COLUMN edited_at TIMESTAMPTZ NULL;

CREATE TABLE message_edits (
  id            UUID PRIMARY KEY,
  message_id    UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  previous_body TEXT NOT NULL,
  edited_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`message_edits` is **required, not optional**. Without it an edit destroys evidence, and this
codebase already treats that as unacceptable — soft delete retains the body for moderation
([messaging.py:95-98](../../../backend/app/models/messaging.py#L95-L98)) and reports snapshot it
([safety/service.py:34-47](../../../backend/app/features/safety/service.py#L34-L47)). Purge it on the
same schedule as soft-deleted bodies, which adds one step to
`architecture_review/MESSAGE_RETENTION_CRON_RUNBOOK.md`.

**Window: 15 minutes**, as `MESSAGE_EDIT_WINDOW_SECONDS` in config. Chosen against two hard
constraints rather than taste: it must exceed the client's 60 s `sendDeadline` so an edit can never
race a retry, and it must be short enough that an edit cannot quietly sanitise a message after
someone reported it.

**Sender only — deliberately asymmetric with delete.** A group admin may delete someone's message;
an admin who could *edit* it would have a forgery primitive. Authorization order: accessible
conversation → `sender_id == actor` → not deleted → inside window → body validation.

**Delete wins over edit.** Check `deleted_at` *inside* the transaction, not before it.
**No push on edit** — only new messages notify.

### 2.4 Drafts — a file per conversation

Mirrors `ChatMessageCache` exactly: `path_provider` +
`<appDocs>/chat_drafts/<sanitized-conversation-id>.json`, best-effort, never breaking chat.

- **Key on the canonical `conversation_id`**, not the addressing id. A DM is addressed by `match_id`
  today, so keying on the addressing id would give one conversation two drafts after the post-cutover
  switch.
- Write debounced ~500 ms on change (the cache already uses 400 ms), plus a synchronous flush in
  `dispose()` and on `AppLifecycleState.paused`.
- Cleared on successful send and when the trimmed field empties.
- Pruned when a thread load returns 403/404 (removed from the conversation), and on any draft
  untouched for 30 days.
- **Deleted on logout and on account deletion** — unsent user text must not outlive the session.
- Deliberately **not** synced across devices: that needs a server round trip per keystroke.

### 2.5 One optimistic-mutation helper, not three

Delete already does optimistic-apply-then-roll-back by hand
([chat_screen_logic.dart:199-216](../../../mobile/lib/features/messages/widgets/chat_screen_logic.dart#L199-L216)).
Reactions, edits and delete are the same shape: mutate locally → call the server → reconcile or
revert. Three hand-rolled copies means three different rollback bugs. Extract the helper with the
first of them (3.6) and migrate delete onto it.

---

## 3. Routes (3.1 + 3.2)

```
/chat/:matchId                    top level  ← was /messages/:matchId
/chat/group/:conversationId       top level  ← was /messages/group/:conversationId
/messages                         shell tab — Chats
/messages/groups                  shell tab — Groups (nested route, not ?tab=)
/messages/new                     stays in the shell (a list-like picker)
```

**Why top level for chat.** It removes the redundant nav bar (#2) *and* a latent crash: the comments
at [app_router.dart:196-211](../../../mobile/lib/core/router/app_router.dart#L196-L211) record that
cross-navigator pushes from inside the shell caused a `'!_debugLocked'` crash which "surfaced as the
app appearing to sign out". Chat still does exactly that kind of push — a group sender's avatar
pushes top-level `/users/:profileId`. So this is a stability fix as much as a UI one.

**Why a nested route for Groups, not a query parameter.** `/messages/groups` gets correct back
behaviour and is deep-linkable without special-casing.

**Compatibility:** keep `/messages/:matchId` and `/discover?tab=groups` as redirects for one release
— live push payloads and saved deep links point at them.

**Side effect worth naming:** Messages is not role-gated, so moving Groups there fixes staff being
unable to reach Groups at all
([discovery_screen.dart:108-115](../../../mobile/lib/features/discovery/screens/discovery_screen.dart#L108-L115)).

---

## 4. Edge cases to design for, not discover

| Case | Resolution |
|---|---|
| Reaction double-tap | Unique constraint makes it idempotent; catch `IntegrityError` and return success, as `persist_message_idempotent` does |
| Reaction/edit frame for a paged-out message | Ignore; the next page load carries the correct state |
| Edit races delete | Delete wins — `deleted_at` checked inside the transaction |
| Delivery boundary arrives out of order | Monotonic advance makes it a no-op |
| Multiple devices | Delivered = *any* device has it; read = *any* device read it. Both are already per-member, not per-device |
| Reaction/edit while offline | Require connectivity in v1 and fail clearly. Queuing these needs the outbox to carry non-message intents — out of scope |
| Reaction by a member who then leaves | Row survives (FK is to `users`, not membership); the aggregate still counts it |
| Edit of a message with a pending report | Allowed — the snapshot and `message_edits` both preserve the original |

---

## 5. Line limits

The `chat_screen.dart` library is 7 files, largest 291 lines, cap 600 — healthy today. Reaction and
edit UI both land in `chat_bubble.dart` (231), and their handlers in `chat_screen_logic.dart` (291).
Plan for two new `part` files up front rather than growing those past the soft target:
`chat_reactions.dart` (chip strip + picker) and `chat_mutations.dart` (the optimistic helper plus
reaction/edit/delete handlers).

---

## 6. Testing

Per item, beyond the obvious:

- **3.0** unsupported frame → soft error and **no** abuse-budget consumption (assert 20 unknown
  frames do not close the socket); client refuses to send a v2 frame when `auth.ok` reports v1.
- **3.1/3.2** no `BottomNavigationBar` in the chat subtree; legacy redirect resolves; a **staff**
  account can reach Groups.
- **3.3** draft survives pop + re-enter and app restart; cleared on send; removed on logout.
- **3.4** boundary advances monotonically and is idempotent; a DM tick reaches ✓✓ only after the
  partner's ack.
- **3.6** toggle idempotent under concurrency; aggregate is **one** query for a 50-message page
  (assert query count, not just correctness).
- **3.7** inside/outside window; forbidden for a group admin who is not the sender; `message_edits`
  row written; delete-wins.

Every API change here moves the OpenAPI snapshot and the route inventory — regenerate deliberately,
and check the diff is only what was intended, as in Phases 1–2.

---

## 7. Settled decisions

All confirmed with the owner before implementation. Recorded here so they read as choices, not
defaults.

1. **Two batches — friction first.** Ship 3.0–3.5 to TestFlight, gather tester feedback, then build
   3.6–3.7. The friction batch adds one nullable column and no tables; reactions and editing add two
   tables and are the only items with schema risk. Reported defects do not wait behind feature work.

2. **Group delivery: DM ticks, "read by" for groups.** DMs get the full
   Sending → Sent → Delivered → Read progression. Groups keep ✓ (sent) and gain a "read by" list on
   long-press. Full ticks in groups would need per-member boundaries held client-side *and* would be
   actively misleading: one member who never opens the app pins every message at ✓ forever.

3. **Read receipts stay unconditional in v1** — recorded as
   [ADR-010](../../../architecture_review/DECISION_LOG.md), with the reciprocity design sketched for
   whenever it is revisited. The reciprocity rule is the part that matters: a toggle that hides your
   receipts while still showing you everyone else's is the version users object to.

4. **No presence feature** — recorded as
   [ADR-009](../../../architecture_review/DECISION_LOG.md). This closes report #22 and completes
   checklist item 3.8.

5. **Emoji set — deferred to Batch 2.** Not needed until reactions are built. Proposal to confirm
   then: 👍 ❤️ 😂 😮 😢 🙏, as a server-side allowlist constant.

---

## 8. Batch 1 work order

The sequence to implement, each step leaving the suite green:

| # | Change | Surface |
|---|---|---|
| 1 | Unsupported-frame handling split from malformed; client retains `protocol_version` | be + fe |
| 2 | Cache envelope `{v, messages}` with a tolerant reader | fe |
| 3 | Chat routes to top level; `/messages` → `Chats \| Groups`; legacy redirects | fe |
| 4 | `ChatDraftStore` | fe |
| 5 | `last_delivered_message_id` + `messages.delivered` / `messages.delivery` frames; `PROTOCOL_VERSION` → 2 | be |
| 6 | Delivered tick, stronger contrast, conversation-row state, group "read by" | fe |

Steps 1–2 are prerequisites and touch no feature behaviour. Step 5 is the only migration, and it is
one nullable column. Deploy order remains server before client throughout.
