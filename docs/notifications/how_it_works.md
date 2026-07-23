# How Notifications Work in LC Connect

A learning-oriented walkthrough of the whole notification system: the *concept* (why a
closed app can't notify itself), then *our actual architecture* (registration, the send
path, delivery, privacy, self-healing), and finally what's built vs. what's still a gap.

> Companion doc: [`firebase_setup.md`](./firebase_setup.md) — the one-time Firebase/APNs setup steps.

---

## 1. The mental model: why we even need Firebase

The single most important idea:

> **A closed (killed) app is not running. Its code cannot execute — so it cannot receive
> your server's message or draw a notification by itself.** The only thing awake on the
> phone is the **operating system**.

So how does WhatsApp buzz your phone when its app is fully closed? The message travels
through the OS's dedicated, always-on **push channel**:

| Platform | Push service | Who runs it |
|----------|-------------|-------------|
| Android  | **FCM** (Firebase Cloud Messaging) | Google |
| iOS      | **APNs** (Apple Push Notification service) | Apple |

Every phone keeps **one** persistent, battery-efficient connection to Google/Apple. Your
server doesn't talk to the phone directly — it hands the notification to FCM/APNs, and
*they* wake the device and show it.

```
  Your backend  ──HTTP──▶  FCM (Google)  ──persistent socket──▶  the phone's OS  ──▶  notification shown
   (has the                 (the bridge)                          (wakes the app
    device token)                                                  only when tapped)
```

**Why we can't do it ourselves:** we can't keep our own WebSocket alive to a closed app —
the OS deliberately kills app sockets in the background to save battery. And a "local
notification" (the app scheduling its own) only fires while the app's code is running,
which is useless for a *server* event arriving at a *closed* app. Hence Firebase.

---

## 2. Three different things people call "notifications"

Keeping these separate avoids most confusion:

| Type | When it shows | In LC Connect |
|------|---------------|---------------|
| **Push notification** (system tray) | App **closed / backgrounded** | ✅ Built (Android verified) |
| **In-app banner / sound** | App **open**, on another screen | ❌ Gap (planned) |
| **Notification bell** (activity feed) | The 🔔 icon on a page | ✅ Shows **connection requests**, *not* messages (by design) |

**Design rule:** messages do **not** go in the 🔔 bell — that's for social activity
(matches, connection requests). Messages surface through push + (planned) unread counts +
an in-app banner. This mirrors WhatsApp/Instagram.

---

## 3. Our architecture — the real flow

### 3a. Registering a device (getting a "token")

A **device token** is FCM's address for one app install on one phone. We must store it so
the backend knows where to send.

```
User signs in
  → NotificationService.registerForUser()          (mobile/lib/core/notifications/notification_service.dart)
     → asks OS for notification permission
     → FirebaseMessaging.getToken()                 → the device's FCM token
     → POST /api/v1/devices { token, platform }     → upserted into the device_tokens table
  → also listens for onTokenRefresh → re-registers  (tokens can rotate)
User signs out
  → NotificationService.clear() → DELETE /devices/{token} + deletes the local FCM token
```

- The table (`device_tokens`) is **idempotent on the token** — re-registering never
  duplicates; logging in as a different user moves ownership.
- This is why, in testing, a logged-out account's old token becomes stale (see §3e).

### 3b. Sending a message → deciding push vs. live

The send goes over the **WebSocket** to the realtime gateway
(`backend/app/features/realtime/gateway.py` → `_on_send`):

```
_on_send:
  1. authorize + persist the message (idempotent, shared with REST)
  2. ACK the sender
  3. broadcast LIVE to the conversation + both users' list channels (real-time update)
  4. Offline check:  is the recipient's open_sockets == 0 ?
        ├─ NO  (recipient online) → do nothing; they got it live. NO push.
        └─ YES (recipient offline) → schedule_offline_push(...)   (fire-and-forget task)
```

### 3c. The grace window (avoids false "offline")

`schedule_offline_push` (`backend/app/features/realtime/runtime.py`) does **not** push
immediately:

```
schedule_offline_push:
  1. wait ~3s   (settings.push_reconnect_grace_seconds)
  2. re-check open_sockets == 0 ?
        ├─ NO  → recipient reconnected during the gap (e.g. Wi-Fi↔cellular) → skip; they'll see it live
        └─ YES → still offline → push_sender.notify_new_message(...)
```

This absorbs quick reconnects so a user flipping networks doesn't get a redundant push for
a message they already saw.

### 3d. Sending to FCM (privacy-first)

`PushSender` (`backend/app/features/notifications/push.py`):

- Initializes firebase-admin from the **`FIREBASE_CREDENTIALS_JSON`** secret (a service
  account). It registers a **named** Firebase app, so every messaging call must pass
  `app=self._app` (a bug we hit: without it, firebase-admin looks for a "default" app and
  fails with *"The default Firebase app does not exist"*).
- **Privacy:** the notification shows the **sender's name only**. The data payload carries
  just ids (`conversation_id`, `sender_id`) — **never the message text**. The app fetches
  the actual message when opened. So message content never sits in a push server or the
  lock screen.

### 3e. Self-healing (stale tokens)

When FCM reports a token is dead (`UnregisteredError` — e.g. the app was uninstalled or the
user logged out), `_send` collects those and `prune_tokens` deletes them. In the logs you'll
see this as `Push: sent=0 failed=1 pruned=1` — that's the system cleaning itself, not an error.

### 3f. Tapping the notification

`FirebaseMessaging.onMessageOpenedApp` reads the payload's `conversation_id` and deep-links
straight into that chat (`/messages/{conversation_id}`). The message body loads from the API
on open.

### 3g. Guarded by design

If `FIREBASE_CREDENTIALS_JSON` isn't set (or Firebase isn't configured on the app), push is
simply **disabled** and everything else runs normally — the backend logs
`Push disabled: FIREBASE_CREDENTIALS_JSON not set`. No crashes, no hard dependency.

---

## 4. How to observe / debug it

The `lc_connect.*` loggers print to the backend console. A healthy offline delivery looks like:

```
[lc_connect.realtime] send: recipient=<id> open_sockets=0 -> scheduling offline push
[lc_connect.realtime] offline push firing: recipient=<id> still offline after grace
[lc_connect.push]     Push: sent=1 failed=0 pruned=0
```

Other lines you'll see and what they mean:

| Log line | Meaning |
|----------|---------|
| `open_sockets=1 -> recipient online, delivered live (no push)` | Recipient was connected → correct, no push |
| `offline push skipped: ... reconnected during grace` | Recipient came back within the 3s window |
| `Push: sent=0 failed=1 pruned=1` | A dead token was auto-removed (self-healing) |
| `Push send failed: The default Firebase app does not exist` | The named-app bug (now fixed) |
| `Push disabled: FIREBASE_CREDENTIALS_JSON not set` | No credential → push off, app still runs |

**Requirement for Android delivery:** the emulator/device must have **Google Play Services**
(use a Play-enabled emulator image), and notification permission must be granted.

---

## 5. Platform status

| Platform | Status |
|----------|--------|
| **Android** | ✅ Verified end-to-end on a real emulator |
| **iOS** | ⏳ Code ready; needs an **Apple Developer account** for the APNs key (see `firebase_setup.md` §4). Until then, iOS gets live in-app delivery but no system push. |

---

## 6. What's built vs. gaps (next work)

**Built & verified:**
- Device-token registration + refresh + logout cleanup
- Offline detection (socket-count) with a reconnect grace window
- FCM delivery, sender-name-only + ids-only payload (privacy)
- Stale-token self-healing
- Tap-to-open deep link
- Guarded init (runs fine with no Firebase)

**Known gaps (planned next):**
1. **Unread counts + badges** — per-conversation, Messages tab, app icon. The backend
   tracks `read_at` per message but has no unread **aggregation** yet, and the UI has no
   unread badge. *(Highest-value gap.)*
2. **In-app banner + sound** — when the app is open but you're on another screen, a new
   message currently updates the list silently. No banner/sound yet.
3. **Drop the socket on background** — tightens the "backgrounded but not fully killed"
   window where the socket lingers and no push fires briefly.

These are enhancements, not bugs — the current system is correct and complete for the
"message to a closed app" case.
