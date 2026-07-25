# The In-App Notification Center

Distinct from **push** ([`how_it_works.md`](./how_it_works.md), which buzzes a *closed* phone via
FCM/APNs), the **notification center** is the in-app feed + bell badge you see *while using the app*:
group membership events and connection events, with a count that ticks up as things happen and clears
when you look.

> Push and the center are complementary: push gets your attention when the app is closed; the center
> is the persistent record you scroll through when it's open.

---

## 1. What it notifies you about

Structured events (not pre-rendered text — the client composes the sentence, so a renamed group/person
always reads correctly):

| Event | Who gets it | Example |
|---|---|---|
| `group_invite` | the invitee | "Alex invited you to CS Club" |
| `group_join_request` | the group's **admins/owner** | "Alex requested to join CS Club" |
| `group_request_approved` / `rejected` | the requester | "You're now a member of CS Club" |
| `group_made_admin` / `group_removed_admin` | the member | "You're now an admin of CS Club" |
| `group_removed` | the member | "You were removed from CS Club" |
| `connection_request` | the receiver | "Alex sent you a connection request" |
| `connection_accepted` | the sender | "Alex accepted your connection request" |

Person-driven rows show the actor's **avatar**; outcome rows show a type icon. Tapping a row opens the
relevant group (or the Connections screen for connection events).

---

## 2. How it's delivered (persistent + live)

The key design decision: **notifications are persisted**, not ephemeral. That's what makes the counter
survive a restart and lets an offline user still see an event on next open.

1. **Emit** — when a group/connection action commits, the backend calls `runtime.emit_notification(...)`,
   which **writes a `Notification` row** (recipient, type, group, actor) and then **publishes a live
   `notification` frame** to the recipient's WebSocket user channel. It's best-effort and failure-isolated:
   a notification failing can *never* break the action that triggered it.
2. **Live** — if the recipient is connected, the frame arrives instantly and the badge increments.
3. **Offline** — no socket? The row still persists. On next app open, the badge **seeds** from the
   server and the row is in the list. (Buzzing a *closed* phone for these is push's job and is not yet
   wired — the in-app store already delivers them on next open.)

Backend: `Notification` model + `app/features/notifications/` (service `create_notification` /
`list_notifications` / `unread_count` / `mark_all_read`) + routes `GET /notifications`,
`GET /notifications/unread-count`, `POST /notifications/read`.

---

## 3. The badge counter (client)

`notificationCountProvider` mirrors the message-unread pattern exactly:

- **seeds** from `GET /notifications/unread-count` once signed in,
- **+1** on each live WS `notification` event,
- **re-seeds** on reconnect and app-resume (so any drift self-corrects),
- **zeroes** when you open the center (which also `POST /notifications/read` — mark-all-read).

The bell renders a **numeric badge** (not just a dot), capped at `99+`, matching the Messages tab.

---

## 4. One bell for everything

There is a **single notification bell** (Home / Connect / Activities headers) → the notification center.
Connection requests appear here *and* the Connections screen still lists actionable pending requests;
the center is the unified feed, and a pinned **"Connection requests"** row at the top keeps
`/connections` reachable with its own live pending count.

---

## 5. Not covered (deferred)

- **Offline push** for these membership/connection events (the in-app store + badge already deliver
  them on next open; the `PushSender` seam is ready if you later want them to buzz a closed phone).
- Notification **grouping**, quiet hours, and per-type preferences.
