# Notifications

Everything about how LC Connect notifies users (push, in-app, and the activity bell).

| Doc | What it's for |
|-----|---------------|
| [`how_it_works.md`](./how_it_works.md) | **Start here.** The concept (why a closed app needs FCM/APNs) + our full architecture: registration, offline detection, delivery, privacy, self-healing, and how to debug it. |
| [`firebase_setup.md`](./firebase_setup.md) | One-time external setup: create the Firebase project, add iOS/Android apps, APNs key, backend `FIREBASE_CREDENTIALS_JSON` secret. |

**Status:** Android push verified end-to-end. iOS is code-ready and waiting on an Apple
Developer account (APNs). Next up: unread counts/badges, then in-app banner + sound.
