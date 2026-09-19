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

| # | Change | Surface | Status |
|---|---|---|---|
| 1 | Unsupported-frame handling split from malformed; client retains `protocol_version` | be + fe | **done** |
| 2 | Cache envelope `{v, messages}` with a tolerant reader | fe | **done** |
| 3 | Chat routes to top level; `/messages` → `Chats \| Groups`; legacy redirects | fe | **done** |
| 4 | `ChatDraftStore` | fe | **done** |
| 5 | `last_delivered_message_id` + `messages.delivered` / `messages.delivery` frames; `PROTOCOL_VERSION` → 2 | be + fe | **done** (wire only; UI is step 6) |
| 6 | Delivered tick, stronger contrast, conversation-row state, group "read by" | be + fe | **done** |

**Step 1, as landed.** `protocol.py` gained `ErrorCode.UNSUPPORTED_FRAME` plus
`KNOWN_INBOUND_TYPES`, derived from the inbound union's own members so the set cannot drift from the
frames the gateway actually accepts, and `is_unsupported_type(raw)`. The gateway checks it *before*
`_tolerate_malformed`, so an unrecognised `type` gets an error frame and spends nothing from the
abuse budget — previously the eleventh such frame in 60s closed the socket with 4429, which the
client retried, earning another ban. `tests/test_realtime_gateway.py` covers the split both ways and
asserts 20 unknown frames leave the socket usable.

Client-side, `RealtimeClient.serverProtocolVersion` and `supportsProtocol(int)` expose what the peer
agreed to. The value is **derived from `status == ready`** rather than reset on disconnect: a socket
is lost through two different paths (`_onClosed` on a drop, `_teardown` on suspend/logout) and a test
caught the drop path keeping a stale `2`, so readiness governs and there is no reset to forget.
A server that omits the field reads as v1; a socket that has not authenticated reads as 0, never as
`kProtocolVersion`.

**Step 2, as landed.** `chat_message_cache.dart` writes `{v, messages}` behind
`chatCacheFormatVersion`, and the reader distinguishes three cases rather than two: a bare array is
the legacy format and still loads (an upgrading user keeps their history), a version *newer* than
this build is discarded unread (a TestFlight rollback is a real occurrence, and a mis-parse is
strictly worse than a refetch), and a map with no `v` at all is not something any build wrote, so it
is discarded too.

Two tolerance fixes came with it, both for damage that previously cost the entire 150-message tail:
an unreadable row is now skipped individually, and an unknown `status` name reads as `sent` instead
of throwing out of `MessageStatus.values.byName`. The second is not hypothetical — step 6 adds
`delivered`, and a rollback would meet exactly that name. `sent` understates a message's progress
without ever claiming it failed, which is the right direction to be wrong in.

**Step 3, as landed.** Conversations are now `/chat/:matchId` and `/chat/group/:conversationId`
at top level; `/messages` is the hub with a `Chats | Groups` switch and `/messages/groups` as a real
nested route. Both legacy conversation locations and `/discover?tab=groups` redirect.

Three things came out of doing it that the design had not called:

* **Ten inline path literals across seven features** were what made this a shim rather than a
  rename. They now live in `features/messages/utils/chat_routes.dart`, so the next move is one edit.
  The navigation test had its own copy of the old route table, which is the kind of duplicate that
  keeps passing while asserting a location the app no longer visits — it imports the helpers now.
* **The route table was untestable.** It lived inline in `routerProvider`, which needs the auth
  notifier, which needs an initialised Supabase client. Extracting `appRoutes()` into
  `core/router/app_routes.dart` makes the *shape* assertable without building a screen:
  `GoRouter(routes: appRoutes()).configuration.findMatch(uri)` resolves a location with no
  BuildContext, no providers and no pumping. `test/core/router/route_table_test.dart` now states
  "a conversation is not inside the shell" as a property, which no widget test can express — it can
  only show that one screen currently happens to have no nav bar. It also halved `app_router.dart`,
  from 410 lines to 193.
* **The segment control missed the 44dp tap target by one pixel** at 43, because the height was an
  artifact of padding plus font metrics. It is a `BoxConstraints(minHeight: 44)` floor now, which
  also survives a larger text scale. The Discovery segments it was modelled on are 34dp and still
  are; that is a separate fix for the Phase 4 a11y sweep.

**Step 4, as landed.** `ChatDraftStore` writes one versioned JSON file per conversation under
`<appDocs>/chat_drafts/`, debounced 500ms on change and flushed on both `dispose` and
`AppLifecycleState.paused`. `draftPruneProvider` runs the 30-day prune once per launch.

Three deviations and one bug worth recording:

* **Keyed on the addressing id, not the canonical `conversation_id`** — §2.4 asked for the latter,
  but it is not known on a cold deep link (`thread` is null there), and keying on it only when
  available would give one conversation two different keys depending on how the user arrived. One
  stable key beats a sometimes-better one. The cost is deferred, not avoided: if DM addressing ever
  moves to `conversation_id`, existing drafts need a one-time rename or they orphan and prune out.
* **Logout cleared nothing at all.** §2.4 says "deleted on logout", and the review said to "extend
  the existing teardown" — there was no teardown. Signing out left both the drafts *and* the cached
  message tails on disk for whoever signed in next, which matters on shared campus devices.
  `_clearLocalChatData()` now clears both before `signOut`, and `ChatMessageCache.clearAll()` exists
  for the second half of that.
* **`flushDraft` threw on every `dispose`.** It read the store through `ref.read`, which Riverpod
  forbids during the tree's finalize pass — so the flush failed in the single commonest case the
  feature exists for (leaving the conversation mid-sentence), and took the timer cancellation below
  it down with it. The store is captured in `initState` now, the way the unread notifier already
  was for exactly this reason. A widget test found it; the unit tests could not have.
* **The widget test needs an in-memory store double**, not a temp directory: `testWidgets` runs in a
  fake-async zone where a real `dart:io` future never completes, and the first version of the file
  hung on its first `await store.load(...)`. The real I/O is covered separately by 19 unit tests.

**Step 5, as landed.** `conversation_members.last_delivered_message_id` (migration
`f2b3c4d5e6a7`), `mark_delivered`, the `messages.delivered` / `messages.delivery` frame pair, and
`PROTOCOL_VERSION` → 2 on both sides. `RealtimeClient.markDelivered` is gated on
`supportsProtocol(2)` and **returns whether it sent**, so step 6 can present delivery as
unavailable on a v1 connection rather than render a tick that never arrives.

* **The monotonic advance is now shared.** `mark_read` and `mark_delivered` need identical
  forward-only semantics, and writing the `(created_at, id)` comparison twice is two places for it
  to be subtly wrong — `_advance_boundary(db, member, field, cursor)` is the one copy, with
  `_cursor_for` and `_member_for` beside it. `mark_read` was refactored onto it and its DB tests
  still pass unchanged, which is the useful signal.
* **The handlers stayed separate.** `_on_delivered` duplicates `_on_read`'s shape rather than
  sharing a parameterised handler, because the two are only *currently* alike: read has a
  display-only mirror on `messages` and drives unread counts, delivery has neither, and reactions
  and edits add further receipt kinds that diverge.
* **The migration named its foreign key explicitly, and that was wrong.**
  `Base.metadata.create_all` produces the server-derived name for the model's unnamed FK, so the
  downgrade could not find the constraint it was written to drop. It is inline and unnamed now, the
  way `last_read_message_id` was in `e5f6a7b8c9d0`, and `drop_column` takes the constraint with it.
  `test_head_revision_downgrades_and_reapplies_without_drift` caught this — the test written two
  sessions ago for exactly this class of error.
* **No backfill, deliberately.** NULL means "nothing acknowledged", which is the honest state for
  every existing row: only an explicit client acknowledgement advances the boundary, and no client
  has ever sent one. Deriving a boundary from message history would claim deliveries that were
  never confirmed.
* **A test of mine had to change**, and for the right reason: it used `messages.delivered` as its
  example of an unknown frame type, which protocol 2 made real. It now uses
  `messages.reaction.added` — still unimplemented, and the same rollout direction.

**Step 6, as landed.** `OutgoingState` + `MessageStatusIcon` (one vocabulary, one widget, used by
both the bubble and the conversation row), `deliveredAt` on `ChatMessage`, `deliveryAckProvider`,
the row's outgoing state, and `GET /messages/{message_id}/read-by` behind a long-press sheet.

* **The receipt handler ignored its own boundary.** `markMineRead()` flipped *every* unread message
  of mine to read whatever message the receipt named. That was invisible with one tick — "all" and
  "up to here" look identical once the partner is caught up, which they usually are — and becomes a
  false claim about another person the moment delivered and read are distinguishable. It is now
  `_advanceMine`, comparing `(createdAt, id)`: the same ordering key the server's boundary uses, so
  the two sides cannot disagree about what "up to here" includes.
* **Delivery is acknowledged at app level, not in the chat screen.** While a conversation is open
  the screen already sends `messages.read`, and read implies delivered — so an acknowledgement there
  adds nothing. The state worth reporting is the other one: the message arrived, this device has it,
  and the user has not opened the conversation. `deliveryAckProvider` listens for
  `conversation.updated` on the user channel, which reaches the device wherever the user is. It is
  deliberately *not* folded into the in-app banner listener: that listener suppresses on being in
  the conversation, being on the Messages list, and being backgrounded, and **none of those suppress
  a delivery** — the device has the message in all three.
* **`OutgoingState` is derived, not a stored enum case.** The review suggested adding `delivered` to
  `MessageStatus`; that field describes the *send attempt*, and a retry can fail after the original
  was delivered, so the two belong in different places. Failure outranks delivery, read outranks
  delivered, and a message with no delivery information reads as `sent` — understating progress
  rather than claiming something untrue.
* **The old tick rendered a dead "Retry".** It printed the label unconditionally while calling
  `onRetry?.call`, so a caller passing no handler got an affordance that did nothing. The label now
  requires a handler.
* **The group answer is a list, not a tick.** A group tick needs a rule for which members count
  *and* every member's boundary held client-side — real state for a glyph nobody asked for.
  `read_by` is one query with a tuple comparison against each member's boundary row (a per-member
  round trip would be ~60ms each across regions), gated by `accessible_conversation` so a message id
  alone cannot enumerate a private group's membership, and it excludes the caller. There is
  deliberately **no timestamp**: a boundary does not record when it passed any particular older
  message, and reporting the boundary's own timestamp would be a guess presented as a fact.
* **The API snapshot changed deliberately** — one route and one schema, verified in the diff before
  regenerating. `MessageReadBy`'s docstring is the public OpenAPI description, so the rationale sits
  in a comment above the class rather than leaking into the contract.
* **A test of mine failed for the right reason twice**: it passed a `User` to `leave_group`, which
  takes a membership row, and silently set `status` on the *account* instead — a suspension. And the
  chat receipt tests needed auth resolved before mounting, because `ChatScreen` captures
  `currentUserId` once in `initState`; a chat that mounts mid-load treats every message as someone
  else's and renders no tick at all.

Steps 1–2 are prerequisites and touch no feature behaviour. Step 5 is the only migration, and it is
one nullable column. Deploy order remains server before client throughout.


---

## 9. Hardening pass over Batch 1

An audit of the shipped batch against security, latency, data structures and tradeoffs. Six real
defects, one of them a regression introduced by this batch. Everything below is fixed and covered by
tests unless marked otherwise.

### 9.1 Unsupported frames had no bound at all — *security, regression*

Splitting "unsupported" from "malformed" in step 1 removed the **only** limit on unknown frames.
Every other inbound frame type has a limiter (`send`, `typing`, `subscribe`, `ping`, `malformed`);
this one had none, so a peer could flood unknown frames indefinitely and have each parsed and
answered. The error also echoed the client's own `type` back verbatim, and frames run to
`WS_MAX_FRAME_BYTES` (8KiB) — a cheap way to make the server generate output.

**Fixed.** `unsupported_limiter` (`WS_MAX_UNSUPPORTED_REPLIES`, default 20/60s) and the echoed type
truncated to 40 characters. Over budget the reply is **dropped silently** — not answered, and not
punished with a close, which is what `_on_ping` already does and the only choice that bounds the work
without bringing back the ban-then-reconnect loop the split exists to prevent. No `render.yaml` entry
needed: it has a safe default.

The limiter tests assert exact reply counts, and the realtime limiters key on `id(conn)` — which
CPython reuses after a free, so a test could inherit a drained bucket from an earlier test's closed
connection. An autouse `prune_idle_buckets(0)` fixture now isolates them; verified stable over
repeated random-ordered runs.

### 9.2 Delivery acknowledgements were quadratic in group size — *latency*

A group bubble shows no delivered tick (§2.1), but every member's device acknowledged every message.
One message in a 30-member group meant 29 acknowledgements, each costing an account recheck, an
authorization, four further queries and a fan-out to all 30 sockets — roughly **170 queries and 870
socket writes to drive a glyph that is never drawn**, growing with the square of group size.

**Fixed** on both sides. The gateway drops a group acknowledgement before any write; the client skips
sending one when it knows the conversation is a group. Server-side is the authoritative bound, since
an older or modified client would otherwise reintroduce the entire cost; the client-side check is the
one that avoids the frames. The client **fails open** when the thread list has not loaded — sending
an acknowledgement the server discards is much better than withholding one a DM's second tick needs.

Read receipts are deliberately *not* suppressed for groups: they drive unread counts, which groups
very much have. Conflating the two would have silently broken group unread.

### 9.3 The boundary write re-resolved the conversation — *latency*

`_on_read` and `_on_delivered` resolve and authorize the conversation, then `mark_read` /
`mark_delivered` resolved it **again**. `resolve_conversation` is always a round trip and never an
identity-map hit — by design, since it matches a conversation id *or* a match id in one statement —
and its own docstring records that this wasted trip "was paid on every read receipt". So this
reintroduced exactly the cost someone had already removed, at ~60ms a time across regions.

**Fixed** by passing the resolved conversation as an optional parameter. Optional rather than
required to avoid churning 21 test call sites for one round trip, and it is an optimisation hint
rather than a second semantic path: nothing downstream trusts it, so a conversation the caller has no
business in still finds no member row and still returns None.

### 9.4 The delivered tick was not durable — *data structure*

The boundary was persisted per member, but **nothing ever returned it**. The state lived only in the
live `messages.delivery` frame, so every page load, app restart and cache miss dropped every second
tick back to one — which a sender reads as "it never arrived". The client was parsing a
`delivered_at` key the server never sent.

**Fixed.** `MessageRead.delivered` is computed from `delivery_cursor`, one query per page rather than
per message (a per-message check over a 50-row page would be ~3 seconds across regions). It is the
**minimum** boundary across other active members, so it means "everyone has it" — and for a DM, where
there is one other member, simply that member's boundary. A member who has acknowledged nothing holds
it at nothing, which is why a group reports nothing rather than something misleading.

**It is a boolean, not a timestamp**, and that is the substantive design change. Delivery is recorded
as a per-member boundary, which does not store *when* it passed any particular older message — so a
`delivered_at` would be a fabricated time for every message but the newest. `read_at` stays a
timestamp because `messages.read_at` is a real per-row column. Two representations of one concept
(a timestamp from the live frame, a boolean from the page) would have been the worse option.

### 9.5 Reading could outrun delivery — *data integrity*

`mark_read` advanced only the read boundary, so a row could hold "read through m5, delivered through
m2" — a state that cannot physically occur, and which anything reading the delivery boundary would
take at face value. **Fixed:** reading advances both. Free — same row, already loaded, no extra query.

### 9.6 `read_by` over-fetched and over-disclosed — *security, latency*

It embedded the full `ProfilePublic` per reader: bio, interests, languages, looking-for, class year,
and a staff `contact_email` — none of which the list renders — and loading it cost four extra
`selectinload` queries **per reader**. A 30-member group meant kilobytes of unrelated personal data
to draw a name and an avatar.

**Fixed:** the row is `{user_id, display_name, avatar_url}`, selected as three columns in the single
existing query. Smaller payload, fewer queries, and a smaller disclosure. The client already parsed
only those two fields, so nothing was lost.

### 9.7 Considered and deliberately not changed

* **Acknowledging the `/sync` backlog.** §2.1 says the boundary "advances when they reconnect and
  `/sync` returns the backlog". Nothing acknowledges that path, and on inspection it should not: a
  message sitting on the server while the recipient was offline is *not* on their device, so
  acknowledging it would be false. The case that matters — catching up in an open conversation — is
  covered, because `sendRead` fires there and reading now advances delivery too (9.5).
* **`id(conn)` as a limiter key** is reused by CPython after a free, so a fresh connection can
  inherit a closed one's bucket. Pre-existing for every realtime limiter, bounded by the idle-bucket
  pruner, and not worth a keying change on its own — but worth knowing before anyone relies on these
  buckets being per-connection with certainty.
* **`_advanceMine` copies the message list per receipt.** O(n) with n ≤ 150 (the cache cap) at human
  pace, and `_stampIfNeeded` already suppresses the rebuild when a re-sent receipt changes nothing —
  which is the case that actually recurs, after every reconnect.

### 9.8 Drafts in a backed-up directory — *resolved: moved to the cache directory*

**Drafts and cached message bodies sat in a backed-up directory.** Both lived under
`getApplicationDocumentsDirectory()`, which iOS includes in iCloud backups and Android in auto-backup.
The message cache predates this work, but **unsent draft text is new**, and it is the most private
content in the feature — it was never shown to anyone.

The options are a genuine tradeoff, not an oversight to fix silently:

| | Privacy | Cost |
|---|---|---|
| Leave in Documents *(current)* | Drafts and cached conversations reach the user's cloud backup | None; drafts survive a device restore |
| Move to the cache directory | Never backed up | The OS may purge a draft under storage pressure |
| Exclude from backup via platform code | Never backed up, never purged | Per-platform native code in both targets |

Logout and account deletion already clear both (deletion routes through `logout()`, verified), so
this was only about the backup surface of an *active* session.

**Decided and done:** drafts moved to `getApplicationCacheDirectory()` — the 30-day prune already
treated them as transient — with `migrateOffBackupPath()` carrying existing drafts across on first
run and removing the old directory. The message cache stays in Documents: it is disposable by
definition, it predates this batch, and moving it would invite the OS to purge conversation history
a user can see.

## 10. Final pre-ship hardening pass

A last sweep over the whole batch before deploying, looking for gaps, security holes, edge cases,
broken paths and anything left unclean. Six real findings; the rest of the review confirmed
existing behaviour and is recorded in §10.7 so it is not re-investigated.

### 10.1 Reactions and edits had no rate limit — *security*

`POST /messages/threads/{id}` was capped at `RATE_LIMIT_MESSAGE_SENDS_PER_MINUTE`, while
`PATCH /messages/{id}` and `PUT`/`DELETE /messages/{id}/reactions/{emoji}` — both added in this
batch — had none. That is the wrong way round for amplification: a send reaches the conversation,
a reaction *also* reaches every member, and an edit reaches the conversation **and** every member's
user channel. Each is cheaper per call than a send and far easier to repeat.

Added `reaction_limit` (60/min) and `message_edit_limit` (20/min), both env-tunable like every other
limit. `test_every_fanning_out_message_write_is_rate_limited` now walks the route table so a future
message endpoint cannot ship uncapped unnoticed.

### 10.2 `POST /activities` was uncapped — *security*

The same sweep over every write endpoint in the app found one more: creating an activity — a durable
object that lands on every student's dashboard — had no limit, while creating a **group** (its exact
analogue) was capped at 5/day and the activity's own *banner upload* was capped. An oversight rather
than a decision, so it is now `activity_create_limit`, 5/day, matching groups.

Admin write routes are deliberately left uncapped: an admin who wants to flood the dashboard can do
it through the console, so a cap there buys nothing and obstructs real bulk work.

### 10.3 Reactions leaked deleted-message existence — *security*

`toggle_reaction` checked `deleted_at` **before** `accessible_conversation`, so a message id alone
answered "this exists, and it was deleted" with a 409 — to anyone, including a user with no access
to the conversation, who should get the same 404 an invented id gives. The docstring already claimed
"a message id alone reveals nothing"; it was true of `edit_message` and `delete_message`, which both
authorize first, and false only here.

Authorization moved ahead of the deletion check. Guessing a v4 UUID is infeasible, so the practical
exposure was nil — but the asymmetry with the two neighbouring functions is exactly the kind that
gets copied.

### 10.4 A long message became a permanently-failing bubble — *broken path*

The server rejects a body over `MAX_BODY_CHARS` on **every** path — REST send, WebSocket send, and
edit. The composer had no cap at all, so a 2001-character message went out optimistically, was
rejected, and settled as a red bubble whose **Retry could never succeed**, however many times it was
pressed. The same dead-end shape as report #8's "Scan again" button on a closed session.

The edit sheet did cap at a hardcoded `2000`. Both now use `kMaxMessageChars` from
`lib/features/messages/data/message_limits.dart`, the client mirror of `app/shared/message_limits.py`
— the composer through a `LengthLimitingTextInputFormatter` (a formatter rather than `maxLength`, so
no character counter appears in the chat bar), the edit sheet through `maxLength`. `maxDraftChars` is
now derived from it rather than restating 4000.

The two constants cannot be shared across the language boundary, so
`tests/test_message_limits_parity.py` asserts them against each other. Drift here is otherwise
invisible until a user pastes something long.

### 10.5 Four sign-out paths skipped the privacy teardown — *privacy*

`_clearLocalChatData()` — which drops cached message bodies and unsent drafts — ran only inside
`logout()`. But most sign-outs are not the user pressing Log out:

| Path | Cause |
|---|---|
| `api_client.dart` Dio interceptor | refresh token finally rejected — **the common one** |
| `auth_provider` bootstrap | a genuine auth failure (not unreachable, which no longer signs out) |
| `auth_provider` sign-in | signed in but never bootstrapped |
| `auth_provider` password reset | session dropped after the update |

All four left cached conversations and unsent drafts on disk for whoever signed in next, which on a
shared campus device is the whole risk the store carries. The teardown moved to the
`AuthChangeEvent.signedOut` listener — the one point every sign-out passes through, whoever started
it — unawaited, because a best-effort disk wipe must not hold up the state change that returns the
user to the login screen. `logout()` keeps its own awaited call so the deterministic path finishes
clearing before the session goes; `clearAll` is idempotent, so running twice costs an empty directory
walk.

### 10.6 A reaction cost two lookups for one answer — *latency*

`toggle_reaction` resolved the message's conversation to authorize the call and then discarded it;
`broadcast_reaction` immediately re-queried the same value to route the fan-out. The toggle now
returns it and the broadcast takes it as a parameter — one round trip instead of two, and the
broadcast can no longer route on a different answer than the write authorized against.

### 10.7 Checked and found correct — do not re-investigate

* **Neither an edit nor a reaction fires a push.** Only new messages do, as specified.
* **Authorization ordering in `edit_message` and `delete_message`** — both authorize before
  revealing existence or state; the sender check returns 404 rather than 403 precisely so a
  non-sender cannot learn a message exists and is merely un-editable.
* **The emoji reaches the server encoded** (`Uri.encodeComponent`) and is allowlist-checked before
  any database work.
* **The reaction picker and edit sheet are reachable end to end** — chat screen → body → list →
  bubble → picker/sheet, both gated on the server's advertised protocol version so a control that
  would 404 is never offered.
* **No dead code from the `service.py` split.** Every apparently-unreferenced name in the messages
  feature is a FastAPI route handler, referenced by decorator.
* **The migration chain is linear with a single head** (`dd7dc4d01780`), so the five queued
  migrations apply cleanly on boot.
* **Client-side URL construction** — every interpolated path segment is a server-issued UUID or a
  compile-time constant; the one query parameter (`?session=`) carries a UUID from our own payload.
* **`kMessageEditProtocolVersion`** was added rather than reusing `kReactionProtocolVersion` for the
  edit gate. Same value today (3), but they are independent capabilities: a later version moving one
  would otherwise silently take the other with it.

### 10.8 Gate

`ruff` clean; **414** backend unit tests, **500** backend integration tests, **674** mobile tests,
`flutter analyze` with no issues, and `check_line_limits.py` passing. The OpenAPI snapshot is
unchanged — every change in this pass is a dependency, an ordering, or a client constant, none of
which alters the contract.
