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
   `com.lcconnect.app`). It must match the App ID registered in Apple Developer *and* the
   `BUNDLE_ID` inside `GoogleService-Info.plist` — FCM addresses APNs by bundle id, so a
   mismatch fails as `DeviceTokenNotForTopic`, which looks exactly like a bad APNs key.
   Note this deliberately differs from the Android package (`com.livingstone.lc_connect`);
   the two registries are independent.
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
   Notifications service (APNs)** → click **Configure** (Apple requires it) and choose:
   - **Environment: `Sandbox & Production`**
   - **Type: `Team Scoped (All Topics)`**
2. Continue → Register → download the `.p8` (**you can only download once** — store it somewhere
   permanent, not `~/Downloads`).
3. Verify on the key's detail page that Configuration reads **`Team Scoped [Sandbox & Production]`**.
4. Firebase console → **Project settings → Cloud Messaging → Apple app configuration** → upload the
   `.p8` to **both** the *development* and *production* APNs auth key rows, with its **Key ID** and
   your **Team ID** (`53D4586HVT`).

> **The environment choice is the trap.** A key created as `Topic specific [Production]` looks
> completely correct everywhere — valid file, right Key ID, right Team ID, both Firebase rows
> filled — and Apple silently refuses every push from a debug build. A `flutter run` build carries
> `aps-environment: development` and registers against the APNs **sandbox**; TestFlight and the App
> Store use **production**. A production-only key covers only the latter, so local testing fails
> while a TestFlight build would have worked. Apple does **not** let you change the environment of
> an existing key — the only fix is to register a new one and revoke the old. Team Scoped +
> Sandbox & Production covers every case and needs no revisiting.

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
- **iOS: no push** → check the backend logs first; they name the cause:
  - `Push: sent=0 failed=N ... reasons=ThirdPartyAuthError` → **APNs refused the credential.** Almost
    always the key's environment (see §4) — a `Topic specific [Production]` key cannot serve the
    sandbox that debug builds register against. Also check Push Notifications is enabled on the App ID.
  - `reasons=SenderIdMismatch` → the device token belongs to a different Firebase project.
  - `reasons=UnregisteredError` → stale token; pruned automatically, no action needed.
  - `offline push skipped: recipient=... reconnected during grace` → push was never attempted because
    the recipient still had a live socket. Background the app and wait ~10s before sending.
  - no push log at all → `push_sender` is disabled, or the recipient had no registered device token.
- **iOS Simulator cannot be trusted for push.** Even on Apple silicon, `getAPNSToken()` commonly
  returns nil, so no FCM token is ever minted and nothing registers. A *successful* simulator push
  proves the config; a failure proves nothing. Validate on a physical device.
- **iOS: nothing registers** → the app logs the reason (`push: ...` lines in
  `core/notifications/notification_service.dart`). `push: APNs token not ready` means APNs never
  issued a token — expected on Simulator, a real problem on a device.
- **`Developer Mode disabled`** on a physical device → iPhone Settings → Privacy & Security →
  Developer Mode → on, then restart. Required before Xcode can register the device for provisioning.
- **Token not registering** → check the device hit `POST /api/v1/devices` (backend logs) and the user
  is verified.
