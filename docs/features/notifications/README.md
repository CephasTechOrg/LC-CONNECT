# Notifications

Everything about how LC Connect notifies users (push, in-app, and the activity bell).

| Doc | What it's for |
|-----|---------------|
| [`how_it_works.md`](./how_it_works.md) | **Push** — the concept (why a closed app needs FCM/APNs) + our full architecture: registration, offline detection, delivery, privacy, self-healing, and how to debug it. |
| [`in_app_center.md`](./in_app_center.md) | **The in-app notification center** — the bell + numeric badge, group membership + connection events, persistent + live WS delivery, and mark-all-read. (Distinct from push.) |
| [`unread_counts.md`](./unread_counts.md) | How the Messages-tab + per-row unread badges work: one backend query, a single-source client provider, live updates, and why it self-corrects. |
| [`firebase_setup.md`](./firebase_setup.md) | One-time external setup: create the Firebase project, add iOS/Android apps, APNs key, backend `FIREBASE_CREDENTIALS_JSON` secret. |
| [`ios_push_setup.md`](./ios_push_setup.md) | **iOS push runbook** — Apple Developer App ID + APNs key, Firebase iOS app, Xcode signing/capabilities/config file, Developer Mode, and a symptom→cause troubleshooting table. Start here for anything iOS. |

**Status:** Android **and iOS** push verified end-to-end on physical devices; unread
counts/badges live and verified. iOS setup is documented in
[`ios_push_setup.md`](./ios_push_setup.md) — read §2 before touching the APNs key.

**Not yet exercised:** TestFlight (production APNs). The key covers it, but that path has not
been tested — do one TestFlight build before inviting testers. Next up: in-app banner + sound
for foreground messages.
