# How Unread Counts Work

The unread badges — the number on the **Messages tab** and the bubble on each
**conversation row** — and how they stay correct in real time without polling.

> Companion docs: [`how_it_works.md`](./how_it_works.md) (push/notification concepts),
> [`firebase_setup.md`](./firebase_setup.md) (Firebase setup).

---

## 1. What "unread" means

A message is **unread by you** when, in one of your conversations, it was sent **by the
partner** (`sender_id != you`) and hasn't been read yet (`read_at IS NULL`).

We reuse the existing `read_at` column — the same one the chat's read-receipts already
set via `mark_read(... through_message_id)`. **No separate "last-read" table**: for a 1:1
campus chat, counting unread rows behind a partial index is simpler and plenty fast.

---

## 2. One golden rule: a single source of truth

The tab badge and the per-row badges **must never disagree**. So there is exactly **one**
place that holds unread state on the client — the `unreadProvider`
(`mobile/lib/features/messages/providers/unread_provider.dart`). Everything reads from it:

```
                    ┌──────────────────────────────┐
                    │  unreadProvider (UnreadState)│
                    │   total: int                 │
                    │   perConversation: {id: n}   │
                    │   activeConversationId       │
                    └──────────────────────────────┘
                        ▲            │
        reads total ────┘            └──── reads perConversation[id]
   (Messages tab Badge)               (each thread row's bubble)
```

If there were two counters (say the tab summed one thing and rows summed another) they
would inevitably drift. One source ⇒ they can't.

---

## 3. Backend: count in one query

`unread_summary(db, user_id)` (`app/features/messages/service.py`) runs a **single grouped
query** — no per-conversation round-trips (no N+1):

```sql
SELECT match_id, count(*)
FROM messages
JOIN matches ON matches.id = messages.match_id
WHERE (matches.user_a_id = :me OR matches.user_b_id = :me)   -- my conversations
  AND messages.sender_id != :me                              -- not my own messages
  AND messages.read_at IS NULL                               -- still unread
GROUP BY match_id
```

- Backed by the partial index **`ix_messages_unread`** on `(match_id, sender_id) WHERE
  read_at IS NULL` — the index only holds *unread* rows, so it stays tiny and the count is
  fast even as history grows.
- Exposed as **`GET /messages/unread-summary`** → `{ total, per_conversation }`.
  Conversations with zero unread are simply omitted.

The backend is the **authority**. The client mirrors it and self-corrects (see §5).

---

## 4. Mobile: seed, then stay live

`unreadProvider` keeps the mirror correct through four events:

| Trigger | What happens |
|---------|--------------|
| **Seed** (app start, after a verified session) | `GET /messages/unread-summary` → fills `total` + `perConversation` |
| **New message arrives** (WS `conversation.updated`) | if it's from the partner **and** not the open chat → `perConversation[id]++`, `total++` |
| **Open a chat** | `clearConversation(id)` → that conversation's count → 0 (optimistic; the real read still goes out over WS) |
| **Reconnect / app resume** | re-seed from the backend → any drift is corrected |

### The "don't count what I'm reading" guard
When a chat is open we set `activeConversationId`. A message arriving **in that open
conversation** is being read live, so it must **not** bump the badge. On leaving the chat we
clear the active id. (The mutation is deferred one microtask past `initState`, because
Riverpod forbids modifying a provider during the build phase.)

### Why "ignore my own"
Every `conversation.updated` carries the full message, so we read `sender_id` straight from
it. If it's mine, skip — I don't have unread messages from myself.

---

## 5. Why it self-corrects (and never gets "stuck")

Live increments are optimistic and could, in theory, drift (a missed event, a race). Two
safety nets make that self-healing:

- **Reconnect re-seed** — whenever the socket reconnects, we re-fetch the summary.
- **App-resume re-seed** — a `WidgetsBindingObserver` re-fetches when the app returns to the
  foreground.

So even in the worst case, the count is only briefly off and snaps back to the backend truth
within seconds — no manual refresh needed.

---

## 6. The UI

- **Messages tab** (`nav_shell.dart`): a Material `Badge` showing `total` (capped `99+`),
  hidden at 0. Watched at the shell so it's live on **every** tab, not just Messages.
- **Conversation row** (`messages_screen.dart`): a count bubble reading
  `perConversation[matchId]`, plus a **bold, darker preview** when unread (WhatsApp-style).

---

## 7. What's deferred (and why)

- **App-icon badge** (the number on the launcher icon): Android support is
  launcher-dependent and unreliable, and it's really driven by the *push payload* — better
  to add alongside iOS push rather than fake it locally now.
- **Cross-device read-sync of the badge** (read on phone A instantly clears phone B's list):
  needs a read event on the *user* channel (today read receipts are conversation-scoped).
  The resume/reconnect re-seed already corrects phone B within seconds, so this is a
  low-value refinement for later.

---

## 8. Quick mental model

> **Backend counts the truth in one query. The client mirrors it, nudges the mirror live on
> each message, zeroes a conversation when you open it, and re-syncs on reconnect/resume — all
> from one provider so the tab and the rows can never disagree.**
