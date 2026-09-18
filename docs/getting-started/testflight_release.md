# Shipping a TestFlight build

The repeatable loop for getting a change in front of pilot testers. Written after the first
release, so the traps below are ones we actually hit.

---

## First: does this even need a new build?

The app talks to a live backend, so a lot is fixable without touching TestFlight at all.

| What changed | What to do |
|---|---|
| Backend / API logic | Push → Render auto-deploys. Reaches **existing installs immediately**. |
| Policy text (`docs/policies/`) | Push, then **manual deploy** of the API service (`lc-connect`) — see the trap below. |
| Employer or admin portal | Push → Render auto-deploys. |
| **Flutter code, app icon, `Info.plist`, assets** | **New build.** Follow the checklist. |

> ⚠️ **Policy edits never auto-deploy the API.** `render.yaml` sets `rootDir: backend`, and Render
> only auto-deploys a service when files *inside its root* change. The policy markdown lives in
> `docs/policies/`, outside `backend/`. The API also `@cache`s documents for the process
> lifetime, so nothing updates until it restarts.
> **Fix: Render → `lc-connect` (the API service, in its own project) → Manual Deploy → Deploy latest commit.**

---

## The checklist

**1. Verify green**
```bash
cd mobile && flutter analyze && flutter test
cd ../backend && .venv/bin/pytest --ignore=tests/db && .venv/bin/ruff check .
cd .. && backend/.venv/bin/python scripts/check_line_limits.py
```

**2. Bump the build number** in `mobile/pubspec.yaml`
- Bug fix → `1.0.0+3`
- Notable changes → `1.0.1+3`

The build number must **always increase and never repeat** — a *failed* upload consumes it too.

**3. Commit and push.** Never build from an uncommitted tree; you can't reproduce the artifact later.

**4. Build**
```bash
cd mobile && flutter build ipa --release
```

**5. Verify the artifact before uploading** — cheaper than an Apple rejection:
```bash
cd /tmp && rm -rf v && mkdir v && unzip -q <repo>/mobile/build/ios/ipa/lc_connect.ipa -d v
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" v/Payload/Runner.app/Info.plist   # must be new
codesign -d --entitlements :- v/Payload/Runner.app 2>/dev/null | grep -o 'aps-environment.*'
```
Expect the new build number and `aps-environment: production`. Production is what TestFlight
uses; a `development` value means push will silently fail for every tester.

**6. Upload** — drag the `.ipa` into **Transporter** → Deliver.

**7. Watch the result.** "Delivered" is not success. Look for **no** *"failed processing"* line, and
the build reaching **Complete** under TestFlight → Build Uploads. Failures arrive within minutes,
by email and in Transporter.

**8. Add it to the tester group** — TestFlight → group → Builds → `+` → new build.
Write a fresh **What to Test** and tick **Automatically notify testers**, or nobody is told.

---

## Does every build get reviewed?

**No.** Only the **first** external build gets a real Beta App Review. After that, builds normally
clear automatically or within a few hours.

A proper review is triggered by **significant changes**:
- a new permission or `NS*UsageDescription`
- a change in what data you collect (also update **App Privacy**)
- a major new feature

**Internal** testing never needs review — which is why the push smoke test belongs there.

These persist across builds and do **not** need redoing: App Privacy answers, the demo account,
the privacy policy URL, and the app-level Beta App Description.

---

## The review demo account

Sign-in requires a `@students.livingstone.edu` or `@livingstone.edu` address, so **a reviewer
cannot self-register.** Without credentials the beta gets rejected at the login screen.

**Test Information → App Review Information → Sign-in required**, with a confirmed account that
already has a completed profile. Keep it working; it is used on every real review.

---

## Traps we hit the first time

| Symptom | Cause |
|---|---|
| `ITMS-90683` missing `NSPhotoLibraryUsageDescription` | `image_picker` uses `ImageSource.gallery`; the purpose string was absent. |
| `ITMS-90683` missing `NSLocationWhenInUseUsageDescription` | `permission_handler_apple` compiles **every** permission strategy into the *release* binary, so `CoreLocation` links and Apple demands a string — even though the app only requests `Permission.camera`. Debug builds don't show this. |
| Build number rejected | A failed upload still consumes the number. Bump again. |
| Build never appears in TestFlight | Processing takes 5–15 min after upload. "No Builds" during that window is normal. |
| Policy page shows old text | The API wasn't manually redeployed (see above). |

---

## Housekeeping

- **Builds expire 90 days** after upload. Re-upload before then or testers lose access.
- Public links can be capped and revoked at any time.
- Tester crash reports land under **TestFlight → Feedback → Crashes**.
