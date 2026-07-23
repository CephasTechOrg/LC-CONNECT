# Push Notifications — Firebase / APNs Setup

The push **code** (backend FCM sender + mobile client) is already implemented and guarded: with no
Firebase config, push is simply disabled and the app runs normally. This guide is the external setup
that turns delivery on. Do it once.

Notifications show the **sender's name only** (never the message body); the app fetches the message
when opened.

---

## 1. Create the Firebase project
1. https://console.firebase.google.com → **Add project** → name it (e.g. `lc-connect`).
2. Skip Google Analytics (optional).

## 2. Add the iOS app
1. Firebase console → **Add app → iOS**.
2. **Bundle ID**: use the app's bundle id (Xcode → Runner target → General; currently
   `com.livingstone.lcConnect`).
3. Download **`GoogleService-Info.plist`** → in Xcode, drag it into the **Runner** target (check
   "Copy items if needed" and the Runner target). Place at `mobile/ios/Runner/GoogleService-Info.plist`.

## 3. Add the Android app
1. Firebase console → **Add app → Android**.
2. **Package name**: `mobile/android/app/build.gradle` → `applicationId`.
3. Download **`google-services.json`** → put it at `mobile/android/app/google-services.json`.
4. Apply the Gradle plugin:
   - `android/build.gradle` (project) `dependencies`: `classpath 'com.google.gms:google-services:4.4.2'`
   - `android/app/build.gradle` (app), at the **bottom**: `apply plugin: 'com.google.gms.google-services'`
   - Ensure `minSdkVersion >= 21`.

## 4. APNs key (required for iOS delivery)
1. Apple Developer → **Certificates, Identifiers & Profiles → Keys → +** → enable **Apple Push
   Notifications service (APNs)** → download the `.p8` (you can only download once).
2. Firebase console → **Project settings → Cloud Messaging → Apple app configuration** → upload the
   `.p8` with its **Key ID** and your **Team ID**.

## 5. iOS capabilities (Xcode → Runner → Signing & Capabilities)
- **+ Capability → Push Notifications**
- **+ Capability → Background Modes** → check **Remote notifications**

## 6. Backend service account (the secret)
1. Firebase console → **Project settings → Service accounts → Generate new private key** → downloads a
   JSON file.
2. Set it as the backend env var **`FIREBASE_CREDENTIALS_JSON`** = the **entire JSON as a string**.
   - Local: add to `backend/.env` (already gitignored). **Never commit the JSON.**
   - Render: **Environment → Secret** `FIREBASE_CREDENTIALS_JSON`.
3. On boot the backend logs `Push enabled (FCM)` when the credential is present (else
   `Push disabled: FIREBASE_CREDENTIALS_JSON not set`).

## 7. Rebuild
```bash
cd mobile/ios && pod install && cd ..
flutter clean && flutter run     # full run, not hot reload
```

## 8. Test
1. Sign in on a device — it requests notification permission and registers its FCM token
   (`POST /api/v1/devices`).
2. **Background or close** that device's app.
3. From the other account, send a message.
4. After a ~3s grace (in case of a quick reconnect), the backgrounded device gets a push with the
   sender's name. Tapping it opens that conversation.

## Security notes
- The service account JSON and the APNs `.p8` are **secrets** — never commit them.
- `GoogleService-Info.plist` / `google-services.json` are client config (not secrets) but are commonly
  gitignored anyway; keep them out of public forks.
- The notification payload carries only `conversation_id` + `sender_id` — no message text.

## Troubleshooting
- **No `Push enabled` log** → `FIREBASE_CREDENTIALS_JSON` not set/invalid on the backend.
- **iOS: no push** → APNs key not uploaded to Firebase, or Push/Background-Modes capabilities missing,
  or testing on the Simulator (iOS Simulator supports notifications on recent Xcode; a real device is
  most reliable).
- **Token not registering** → check the device hit `POST /api/v1/devices` (backend logs) and the user
  is verified.
