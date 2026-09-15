# iOS Push — Setup Runbook

How iOS push notifications were set up for LC Connect, in the order you'd do it again.

Android needs none of this (just `google-services.json`). Everything here is iOS-only, because
Apple sits between Firebase and the device and has to authorise every message.

**Do the steps in order.** Several of them can't be verified until a later one is done, so
skipping ahead is how you end up debugging the wrong thing.

---

## The values

Everything below has to agree. A mismatch anywhere produces silence, not an error.

| What | Value | Where it lives |
|---|---|---|
| Bundle ID | `com.lcconnect.app` | Xcode, Apple App ID, Firebase iOS app, `GoogleService-Info.plist` |
| Team ID | `53D4586HVT` | Apple (App ID Prefix), Firebase APNs upload |
| APNs Key ID | `4XBN3BAYC8` | Apple Keys, Firebase APNs upload |
| Firebase project | `lc-connect-7abe7` | must be the **same project as Android** |
| Sender ID | `998316406519` | inside both client config files |

> The iOS bundle ID deliberately differs from the Android package
> (`com.livingstone.lc_connect`). They're separate registries; this is fine.

---

## 1. Apple Developer — register the App ID

**Certificates, Identifiers & Profiles → Identifiers → `+` → App IDs → App**

- Description: `LC Connect`
- Bundle ID: **Explicit** → `com.lcconnect.app`
- Capabilities: tick **Push Notifications**
- **Save**

⚠️ Ticking Push Notifications is not optional. Without it Apple refuses every message for this
bundle, and the failure arrives as a generic credential error that looks like a bad key.

---

## 2. Apple Developer — create the APNs key

**Keys → `+`**

- Key Name: `LC Connect APNs Key`
- Tick **Apple Push Notifications service (APNs)**
- Click **Configure** (Apple requires it) and set:
  - **Environment: `Sandbox & Production`**
  - **Type: `Team Scoped (All Topics)`**
- Continue → Register → **Download**

Then open the key's detail page and confirm Configuration reads **`Team Scoped [Sandbox &
Production]`**.

🔥 **This is the trap that cost us most of a day.** A key created as `Topic specific
[Production]` looks perfect everywhere — valid file, correct Key ID and Team ID, both Firebase
rows filled — and Apple silently refuses every push from a debug build.

The reason: a `flutter run` build carries `aps-environment: development` and registers against
the APNs **sandbox**. TestFlight and the App Store use **production**. A production-only key
serves only the latter, so local testing fails while a TestFlight build would have worked.

**Apple does not let you change a key's environment afterwards.** The only fix is to register a
new key and revoke the old one. Team Scoped + Sandbox & Production covers every case forever.

🔑 The `.p8` downloads **once**. Store it in a password manager, not `~/Downloads`. It's a
secret — `.gitignore` already blocks `*.p8`. You may hold at most two APNs keys per account.

---

## 3. Firebase — add the iOS app

Open the **existing** project `lc-connect-7abe7` — do **not** create a new one. The backend
authenticates with one service account scoped to that project; an app in a different project
would make every push fail as a sender-ID mismatch.

**Project settings → General → Your apps → Add app → iOS**

- Bundle ID: `com.lcconnect.app` (copy-paste; the capitalisation matters)
- Download **`GoogleService-Info.plist`**

Then **skip the rest of the wizard.** "Add Firebase SDK" and "Add initialization code" are for
native iOS apps. This is Flutter: the SDK comes from the `firebase_core` / `firebase_messaging`
packages, and Firebase is initialised from Dart in `main.dart`. Adding the SDK again via Swift
Package Manager gives you two copies of Firebase and duplicate-symbol link errors.

Click **Next → Next → Continue to console**. The downloaded file was the only thing that mattered.

---

## 4. Firebase — upload the APNs key

**Project settings → Cloud Messaging → Apple app configuration → APNs Authentication Key**

Upload the same `.p8` to **both** rows:

| Row | Why |
|---|---|
| Development APNs auth key | debug builds (`flutter run`) → APNs sandbox |
| Production APNs auth key | TestFlight + App Store → APNs production |

Key ID `4XBN3BAYC8`, Team ID `53D4586HVT` for both. Ignore the **APNs Certificates** section
entirely — that's the older mechanism, and certificates expire where keys don't.

---

## 5. Xcode — signing, capabilities, config file

Open **`mobile/ios/Runner.xcworkspace`** (not `.xcodeproj`).

Select the blue **Runner** icon → **TARGETS → Runner** → **Signing & Capabilities**:

1. ✅ **Automatically manage signing**
2. **Team** → `53D4586HVT` (sign in via Xcode → Settings → Accounts if the list is empty)
3. **+ Capability** → **Push Notifications**
4. **+ Capability** → **Background Modes** → tick **Remote notifications**
5. Add the config file: select the yellow **Runner** folder, then
   **File → Add Files to "Runner"…** → pick `GoogleService-Info.plist` →
   ✅ **Copy items if needed**, and ✅ **Runner** under *Add to targets*

⚠️ **Step 5 is the silent killer.** Copying the plist into the folder is not enough — it must be
in the target's *Copy Bundle Resources* phase or it never ships inside the app. Firebase then
finds nothing, `Firebase.initializeApp()` throws, and the app catches it and disables push with
no visible error.

⚠️ **Use File → Add Files, not drag-and-drop.** Dropping the file on the *entitlements editor*
instead of the file tree silently adds bogus `com.apple.developer.applesignin` and iCloud
entitlements, which then fail code signing.

Verify from the terminal rather than trusting the UI:

```bash
cd mobile
flutter build ios --no-codesign --debug
ls build/ios/iphoneos/Runner.app/GoogleService-Info.plist   # must exist
cat ios/Runner/Runner.entitlements                          # aps-environment only
```

> **No CocoaPods.** This project resolves plugins through Swift Package Manager, so there is no
> `Podfile` and `pod install` is not part of the flow.

---

## 6. The test device

Push **cannot be validated on the Simulator.** Even on Apple silicon, `getAPNSToken()` commonly
returns nil, so no FCM token is ever minted and nothing registers. A *successful* simulator push
would prove the config; a failure proves nothing. Use a physical iPhone.

On the phone: **Settings → Privacy & Security → Developer Mode → on**, then restart and confirm.
Xcode can't register the device for provisioning until this is done — it shows
*"Developer Mode disabled"* under Window → Devices and Simulators.

Then plug in, trust the Mac, and click **Try Again** on the Signing warning. Until a device is
registered, Apple reports *"Your team has no devices from which to generate a provisioning
profile."*

Only the **receiving** device must be real. The sender can be a Simulator.

---

## 7. Backend

`FIREBASE_CREDENTIALS_JSON` — the Firebase service-account JSON, entire contents, multi-line.

- Local: `backend/.env`
- Render: **Environment** tab (it's `sync: false` in `render.yaml`, so it is *not* in the repo)

On boot the logs say `Push enabled (FCM)`, or `Push disabled: FIREBASE_CREDENTIALS_JSON not set`
— in which case push is silently off, with everything else correct.

---

## 8. Test it

1. `flutter run -d <iphone-id>` — first launch needs
   **Settings → General → VPN & Device Management → Trust**
2. Sign in, allow notifications. The console must print:
   `push: device registered with backend (ios)`
3. Confirm the token reached the server:
   ```sql
   SELECT platform, left(token, 24) AS token_prefix, updated_at
   FROM device_tokens ORDER BY updated_at DESC LIMIT 20;
   ```
4. **Background the app and wait ~10 seconds.** The backend only pushes when the recipient has
   zero live sockets, re-checked after a 3s grace (`PUSH_RECONNECT_GRACE_SECONDS`). Send too soon
   and it correctly decides you're still online.
5. Send a message from the other account. Backend logs should read:
   ```
   offline push firing: recipient=... still offline after grace
   Push: sent=1 failed=0 pruned=0
   ```

---

## Troubleshooting — symptom to cause

Always read the **backend logs** first; they name the cause.

| Log line | Cause |
|---|---|
| `reasons=ThirdPartyAuthError` | Apple refused the credential. Key environment (§2) or Push not enabled on the App ID (§1). |
| `reasons=SenderIdMismatch` | Token belongs to a different Firebase project. |
| `reasons=UnregisteredError` | Stale token (app uninstalled). Pruned automatically; no action. |
| `offline push skipped: ... reconnected during grace` | Push never attempted — recipient still had a live socket. Wait longer before sending. |
| nothing at all | `push_sender` disabled (§7), or the recipient has no registered token (§8 step 3). |

App-side, `flutter run` prints the reason too:

| Console line | Cause |
|---|---|
| `push: device registered with backend (ios)` | ✅ working |
| `push: APNs token not ready — waiting for onTokenRefresh` | APNs issued no token. Expected on Simulator; on a device check §5 capabilities. |
| `push: POST /devices failed: ...` | Token obtained, backend rejected it. |
| `Push disabled (Firebase not configured)` | The plist isn't in the app bundle (§5 step 5). |

---

## Before inviting testers

Everything above validates the **sandbox** path. TestFlight uses **production**. The Team Scoped
key covers both, but nobody has exercised that path until you try it.

**Ship one TestFlight build and get a push on your own phone before inviting anyone.** It is the
only test that matches what your testers will actually run.
