# LC Connect — Real-Time Messaging

This document explains how real-time message delivery works in LC Connect end-to-end: the Supabase configuration, the Flutter client subscription code, the deduplication strategy, and the rationale behind every decision.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture Diagram](#2-architecture-diagram)
3. [Supabase Side Setup](#3-supabase-side-setup)
4. [Flutter Side Setup](#4-flutter-side-setup)
5. [How the Chat Screen Works](#5-how-the-chat-screen-works)
6. [Deduplication Strategy](#6-deduplication-strategy)
7. [Message Send Flow](#7-message-send-flow)
8. [Message Receive Flow](#8-message-receive-flow)
9. [Lifecycle — Subscribe and Unsubscribe](#9-lifecycle--subscribe-and-unsubscribe)
10. [Why Not Polling](#10-why-not-polling)
11. [Known Limitations](#11-known-limitations)
12. [Future Improvements](#12-future-improvements)

---

## 1. Overview

Before real-time was implemented, `chat_screen.dart` used a simple one-shot HTTP fetch: `_fetchMessages()` was called once in `initState()` and the list never updated until the user left and re-opened the screen.

After real-time was implemented:
- The initial message history still loads via a single HTTP call to the FastAPI backend.
- A **Supabase Realtime channel** subscription listens for `INSERT` events on the `messages` table filtered by `match_id`.
- When a new message row is inserted into Postgres (by any party in the conversation), the Flutter client receives the event immediately and appends it to the visible list.
- The sender sees their message immediately via optimistic add from the API response.
- The receiver sees incoming messages appear live without any polling or refresh.

---

## 2. Architecture Diagram

```text
Sender (Flutter)
    │
    │  POST /messages/threads/{match_id}   (FastAPI backend, requires JWT)
    ▼
FastAPI Backend
    │
    │  INSERT INTO messages (match_id, sender_id, body, ...)
    ▼
Supabase Postgres (messages table)
    │
    │  WAL → supabase_realtime publication → Realtime server
    ▼
Supabase Realtime WebSocket
    │
    │  PostgresChanges INSERT event (filtered to this match_id)
    ▼
Receiver Flutter App (Supabase channel subscription)
    │
    │  Appends new ChatMessage to _messages list
    ▼
ListView re-renders → auto-scrolls to bottom
```

Writes always go through the FastAPI backend (so JWT auth is enforced). Reads for real-time delivery go through Supabase directly (filtered by match_id, protected by anon RLS policy).

---

## 3. Supabase Side Setup

There are two things to set up in Supabase before real-time works. Both are one-time operations.

### 3.1 Enable Realtime publication on the messages table

```
Supabase Dashboard → Database → Replication → supabase_realtime → Tables → messages (public) → toggle ON
```

The `supabase_realtime` publication is a Postgres logical replication publication. Enabling a table on it means Supabase will forward changes from that table to connected Realtime clients.

There are two entries named "messages" in the table list:
- `schema: public, table: messages` — **enable this one**
- `schema: realtime, table: messages` — Supabase internal, leave it alone

After toggling on, verify with SQL:

```sql
SELECT schemaname, tablename
FROM pg_publication_tables
WHERE pubname = 'supabase_realtime';
-- Should include: public | messages
```

### 3.2 RLS policies for messages — JWT-based security

LC Connect uses custom FastAPI JWT auth (not Supabase Auth). The JWT is wired into the Supabase Realtime client so that `auth.uid()` resolves to the logged-in user's UUID inside RLS policies. This means Supabase can enforce per-user read access at the database level.

**Full setup details and rationale:** see `lc_connect_docs/security_rls_messages.md`

**Summary of what is in place:**

Two policies are active on the `messages` table:

```sql
-- Only match participants can read their messages
CREATE POLICY "participants can read their messages"
ON messages FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM matches
    WHERE matches.id = messages.match_id
      AND (matches.user_a_id = auth.uid() OR matches.user_b_id = auth.uid())
  )
);

-- No direct inserts via client keys — all writes go through FastAPI
CREATE POLICY "no direct inserts"
ON messages FOR INSERT
WITH CHECK (false);
```

**How `auth.uid()` works here:**

Three things had to be in place for this to function:

1. The FastAPI JWT payload includes `'role': 'authenticated'` — required for Supabase to treat the connection as an authenticated user
2. The Supabase JWT Secret (Dashboard → Project Settings → Auth → JWT Settings) is set to the same value as the backend `JWT_SECRET_KEY`
3. After every login/register, `Supabase.instance.client.realtime.setAuth(token)` is called in `auth_provider.dart` so the realtime channel carries the user's identity

Without step 3, the realtime client connects anonymously and `auth.uid()` returns NULL, silently blocking all events.

**The migration file** for these policies lives at `supabase/migrations/20260510000000_messages_rls.sql`. Run this after any Supabase reset or when creating a new environment.

---

## 4. Flutter Side Setup

### 4.1 Add supabase_flutter package

In `lc_connect_mobile/pubspec.yaml`:

```yaml
dependencies:
  supabase_flutter: ^2.8.0
```

Then run:

```bash
flutter pub get
```

### 4.2 Initialize Supabase in main.dart

`Supabase.initialize()` must be called before `runApp`. It requires `WidgetsFlutterBinding.ensureInitialized()` first.

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(const ProviderScope(child: LcConnectApp()));
}
```

The `SUPABASE_URL` and `SUPABASE_ANON_KEY` come from `lc_connect_mobile/.env`. The anon key is safe to put here — it is the public-facing key, not the service role key.

### 4.3 Flutter .env values needed

```env
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

Find the anon key at: **Supabase → Settings → API → Project API Keys → anon public**.

---

## 5. How the Chat Screen Works

The chat screen (`chat_screen.dart`) has two concurrent mechanisms:

| Mechanism | Purpose | Trigger |
|---|---|---|
| `_fetchMessages()` | Load message history from FastAPI | Once, in `initState()` |
| `_subscribeToMessages()` | Receive new messages live | Runs from `initState()`, stays active until `dispose()` |

Both run in parallel from `initState()`. The history fetch populates `_messages` and seeds `_seenIds` with all existing message IDs. The subscription then adds only genuinely new messages.

### State fields added for real-time

```dart
final _seenIds = <String>{};   // tracks IDs already in the list
RealtimeChannel? _channel;     // the active Supabase channel subscription
```

---

## 6. Deduplication Strategy

Without deduplication, a message sent by the current user would appear twice:
1. Once from the `_send()` response (optimistic add)
2. Again from the Supabase Realtime INSERT event

The `_seenIds` set prevents this. Every time a message is added to `_messages`, its `id` is recorded in `_seenIds`. Before adding any message from any source, the code checks:

```dart
if (_seenIds.contains(msg.id)) return;  // already displayed, skip
_seenIds.add(msg.id);
_messages.add(msg);
```

This applies to:
- Messages loaded from the history fetch (`_fetchMessages`)
- Messages received via Realtime subscription
- Messages added optimistically from the `_send()` API response

---

## 7. Message Send Flow

When the current user sends a message:

```
User taps send
→ _send() clears the input field
→ setState: _sending = true  (shows spinner on send button)
→ POST /messages/threads/{matchId}  (FastAPI, requires JWT)
→ API returns the created ChatMessage with its server-assigned ID
→ If ID not in _seenIds: add to _messages and _seenIds (optimistic display)
→ setState: _sending = false
→ _scrollToBottom()
```

Separately, Supabase Realtime will also receive the same INSERT event. When it arrives:

```
Realtime INSERT callback fires
→ Parse payload.newRecord into ChatMessage
→ _seenIds.contains(msg.id) → TRUE (already added by _send)
→ return early — no duplicate
```

The sender sees their message instantly (from the API response), and the Realtime event is silently deduplicated.

---

## 8. Message Receive Flow

When the other user sends a message:

```
Other user's FastAPI call inserts row into messages table
→ Supabase WAL captures the INSERT
→ Realtime server evaluates RLS (anon SELECT policy allows it)
→ Realtime server checks the channel filter: match_id = {this match_id}
→ Event is forwarded to all subscribed clients for this match_id
→ Flutter callback fires:
    - payload.newRecord is the new message row as Map<String, dynamic>
    - ChatMessage.fromJson(payload.newRecord) parses it
    - _seenIds check: ID not in set → add and display
    - setState: _messages.add(msg)
    - _scrollToBottom()
```

The receiver sees the new message appear in the chat list without any action.

---

## 9. Lifecycle — Subscribe and Unsubscribe

The channel is created in `initState()` and cleaned up in `dispose()`:

```dart
@override
void initState() {
  super.initState();
  _currentUserId = ref.read(authNotifierProvider).asData?.value?.id ?? '';
  _fetchMessages();          // load history
  _subscribeToMessages();    // start realtime subscription
}

@override
void dispose() {
  _channel?.unsubscribe();   // stop the WebSocket subscription
  _inputController.dispose();
  _scrollController.dispose();
  super.dispose();
}
```

Calling `_channel?.unsubscribe()` in `dispose()` is important. Without it, the channel stays open after the user navigates away, wasting resources and potentially delivering events to a widget that no longer exists.

### The subscription setup

```dart
void _subscribeToMessages() {
  _channel = Supabase.instance.client
      .channel('messages:${widget.matchId}')     // unique channel name per conversation
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,        // only new messages
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,      // WHERE match_id = {matchId}
          column: 'match_id',
          value: widget.matchId,
        ),
        callback: (payload) {
          if (!mounted) return;
          final msg = ChatMessage.fromJson(payload.newRecord);
          if (_seenIds.contains(msg.id)) return;
          setState(() {
            _seenIds.add(msg.id);
            _messages.add(msg);
          });
          _scrollToBottom();
        },
      )
      .subscribe();
}
```

Key points:
- Channel name `'messages:${widget.matchId}'` is unique per conversation. Multiple chat screens (if somehow open) would each get their own channel.
- `PostgresChangeEvent.insert` means only new messages trigger the callback. Updates and deletes do not fire (message editing/deletion is not yet a feature).
- The server-side filter `match_id = {matchId}` means Supabase only forwards events for this specific conversation — users cannot receive messages intended for other conversations.
- `if (!mounted) return` guards against setState being called after dispose.

---

## 10. Why Not Polling

The previous implementation called `_fetchMessages()` once in `initState()` and never again. The user had to leave and re-open the chat to see new messages.

Polling (calling `_fetchMessages()` on a timer) was considered and rejected:

| Issue | Details |
|---|---|
| Battery drain | Even at 3-second intervals, constant HTTP calls drain battery |
| Render free tier | Each poll wakes the backend; Render free tier spins down after 15 min, so frequent polls increase response latency |
| Unnecessary load | Backend handles API calls from all users; polling multiplies requests with zero benefit |
| Still not instant | 3-second polling means up to 3 seconds before a message appears |

Supabase Realtime uses a persistent WebSocket. The connection is maintained, and events arrive in under 200ms in most cases.

---

## 11. Known Limitations

### Realtime requires internet

There is no offline message queue. If the device loses connection, incoming messages are missed until the subscription reconnects. `supabase_flutter` handles reconnection automatically, but events during the offline window are not replayed.

### Only INSERT events

The subscription listens to `PostgresChangeEvent.insert` only. If a message is edited or deleted in the future, a separate subscription or logic would be needed.

### Thread list does not auto-update

The messages screen (`messages_screen.dart`) shows a list of conversations. It does not have a Realtime subscription. When a new message arrives in a conversation, the thread list preview does not update until the user pulls to refresh or navigates away and back. This is a future improvement.

---

## 12. Future Improvements

| Improvement | What it requires |
|---|---|
| Thread list live preview | Add a Realtime subscription in `messages_provider.dart` for latest message updates |
| Read receipts | INSERT into a `message_reads` table; add Realtime subscription for that table |
| Typing indicators | Use Supabase Realtime Broadcast (not Postgres changes) — no DB write needed |
| Offline message queue | Local database (e.g., `sqflite`) to store pending messages when offline |
| Push notifications | Firebase Cloud Messaging triggered by backend webhook when message is inserted |
