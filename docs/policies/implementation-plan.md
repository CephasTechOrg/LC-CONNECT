# Policy acceptance — implementation plan

How the Terms of Service, Privacy Policy and Employer Agreement get in front of users and get
recorded. Ordered so each phase leaves the repo green and shippable.

---

## The one decision that shapes everything

You said **users must accept before the account is created**. There is a wrinkle worth naming
before we build, because it decides where the code goes.

"Before the account is created" and "recorded somewhere we can trust" pull apart:

- The account is created by `supabase.auth.signUp()`, called **directly from the phone**. At that
  moment there is no session and no LC Connect user row — so there is nothing server-side to write
  acceptance against.
- The first moment a trustworthy record is possible is `POST /auth/bootstrap`, which runs after the
  email code is confirmed. By then the Supabase account exists.

**The resolution: gate the UI before signup, persist the record at bootstrap.**

1. **Signup screen** — an explicit checkbox. `signUp()` is not called until it is ticked. Nobody
   creates an account without having accepted. This satisfies the requirement as a user experiences
   it.
2. **Carried through signup metadata** — the accepted version rides along in
   `signUp(data: {...})`, exactly as `contact_email` already does.
3. **Persisted at bootstrap** — the backend reads it from the JWT claims and writes it to the
   `users` row, the same way `contact_email` is synced today.
4. **Re-gated server-side** — if bootstrap finds no acceptance (tampered client, an account made
   before this shipped, or a version bump), the app is sent to a full-screen accept gate before it
   can go anywhere else.

Step 4 is what makes step 1 more than decoration. The checkbox is the UX; the bootstrap check is
the enforcement. A client that skips the checkbox still hits the gate.

---

## Where the policy text lives

**Serve it from the API, with the markdown files in this folder as the source of truth.**

The alternative — bundling the markdown as Flutter assets — means a policy fix needs an App Store
release, and the two web portals would each need their own copy. One endpoint avoids all of that.

- `GET /api/v1/policies` → the list, with the current version
- `GET /api/v1/policies/{slug}` → one document's markdown (`terms-of-service`, `privacy-policy`,
  `community-guidelines`, `employer-agreement`)

Both **unauthenticated** — you must be able to read the terms before you have an account.
`features/lookups/router.py` is the existing precedent for a public endpoint, so this is not a new
pattern.

The backend reads the files from `docs/policies/` at startup and caches them in memory. No database
table, no admin CMS — the files are already version-controlled and reviewed through pull requests,
which is the right workflow for a legal document.

---

## Phase 1 — Backend: record and serve

**Migration** (`alembic`, head is `f5a6b7c8d9e0`), following
`d3e4f5a6b7c8_add_user_contact_email.py`:

```python
op.add_column('users', sa.Column('policies_accepted_version', sa.Integer(), nullable=False,
                                 server_default='0'))
op.add_column('users', sa.Column('policies_accepted_at', sa.DateTime(timezone=True), nullable=True))
```

`server_default='0'` matters: every existing account becomes "has not accepted", which is exactly
right — they will be gated on next launch.

**New** `app/shared/policy_versions.py`:

```python
CURRENT_POLICY_VERSION = 1
```

One constant, mirroring `CURRENT_CONSENT_VERSION` in the scholar service. Bump it to re-prompt
everyone.

**New** `app/features/policies/` — `router.py` + `service.py`. The service loads and caches the
markdown; the router serves it.

**Changed** `app/features/auth/service.py` — in `_sync_and_return`, read the accepted version from
claims metadata and persist it if it is newer than what is stored. Sits next to `_sync_contact_email`
and works the same way.

**Changed** `app/features/auth/router.py` + `schema.py` — `BootstrapResponse` and
`CurrentUserResponse` gain `policies_accepted: bool` (computed as
`stored_version >= CURRENT_POLICY_VERSION`). A boolean, not the raw version, so the client never
has to know the numbering.

**New** `POST /auth/accept-policies` — authenticated, records acceptance for the signed-in user.
This is what the re-consent gate calls, and what covers accounts created before this shipped.

> Regenerates the OpenAPI snapshot (`UPDATE_SNAPSHOTS=1`) — an intentional API change.

**Tests:** version stored from claims · older version does not overwrite newer · `policies_accepted`
false at version 0 · `/policies/{slug}` reachable with no token · unknown slug 404s ·
`accept-policies` sets version and timestamp.

---

## Phase 2 — Mobile: read the policies

`flutter_markdown` is **not** currently a dependency, and adding it for this is the right call —
hand-rolling a markdown renderer for a legal document is how you end up with a clause that fails to
display.

- **New** `lib/features/policies/providers/policies_provider.dart` — fetches and caches a document.
- **New** `lib/features/policies/screens/policy_document_screen.dart` — full-screen reader: title,
  scrollable markdown body, a back arrow, and a "Last updated" line. Reuses `AuthTextField`'s
  typography conventions so it does not look bolted on.
- **New** `lib/features/policies/widgets/policy_links.dart` — the inline "Terms of Service" /
  "Privacy Policy" links, shared between the signup checkbox and the gate screen.

Route: `/policies/:slug`, pushed (not `go`) so the back arrow returns you to where you were —
mid-signup with your form intact. This is the same push-versus-replace point that bit the register
screen.

**Offline:** the reader needs network on first open. Cache each document once fetched, so a user who
has read them can reopen them offline.

---

## Phase 3 — Mobile: the signup checkbox

On `register_screen.dart`, below the password fields and above **Create Account**:

```
┌──────────────────────────────────────────────┐
│ ☐  I agree to the Terms of Service and       │
│    Privacy Policy, and I confirm that the    │
│    email addresses above are mine.           │
└──────────────────────────────────────────────┘
```

- "Terms of Service" and "Privacy Policy" are tappable and open the reader.
- Unticked → **Create Account** is disabled. Not an error after the fact; the button simply is not
  available. That is clearer than letting someone press it and be told no.
- The one sentence carries **both** attestations from decisions #9 and #10 — the policies *and*
  that the addresses are theirs. Folding them together keeps it to one checkbox; splitting into
  three would get tapped through without reading.
- It sits **above** the button and **below** the fields, so "the email addresses above" refers to
  something visible.

The confirm sheet already summarises both addresses before anything is sent, so the attestation and
the review reinforce each other rather than duplicating.

**Wiring:** `register()` passes `policiesAcceptedVersion` into `signUp(data: {...})` alongside
`contact_email`.

**Tests:** button disabled until ticked · tapping a link opens the reader and returns with the form
intact · accepted version reaches `register()`.

---

## Phase 4 — Mobile: the acceptance gate

For anyone who reaches bootstrap without a current acceptance — existing pilot accounts, a version
bump, or a tampered client.

**New** `lib/features/policies/screens/policy_gate_screen.dart`, route `/accept-policies`:

- Heading: "Before you continue" — or "We have updated our terms" when the stored version is
  non-zero, since those are different situations and should not read identically.
- Short plain summary of what they are agreeing to, not the full text.
- Links to read each document in full.
- **Accept and continue** → `POST /auth/accept-policies`, then refresh and proceed.
- **Sign out** → the way out, so this screen is never a trap. The onboarding lock taught us that
  every forced screen needs an exit.

**Router** (`app_router.dart`), inserted between verified and onboarding:

```
not logged in            → /login
logged in, not verified  → /verify-email
verified, not accepted   → /accept-policies      ← new
accepted, no profile     → /onboarding
otherwise                → /home
```

Policies before onboarding, because onboarding is the first point where a user creates content
about themselves.

**Tests:** gate appears for `policies_accepted: false` · accepting advances to onboarding · sign-out
works · a user who already accepted never sees it · re-consent copy differs from first-time copy.

---

## Phase 5 — Employer portal

Employers accept the [Employer Agreement](employer-agreement.md) before reaching scholar data.

- Backend: `employer_accounts` gets the same two columns and the same `POST` endpoint, scoped to
  employer auth.
- Frontend: a gate in `employer-portal/app/(dashboard)/layout.tsx` — it wraps every dashboard page,
  so one check covers `/scholars`, `/scholars/[id]` and `/opportunities` without touching each.
- Same shape as mobile: summary, full text, Accept, Sign out.

This matters more than the mobile gate in one respect: it is the only thing standing between an
approved employer account and student résumés.

---

## Phase 6 — Admin portal and footers

Per decision #5, **admins get no gate** — they are covered by employment terms.

What they do get: policy links in the portal footer, so the documents are reachable. Same for the
employer portal and the mobile Settings screen. A policy nobody can find after signup is not much
of a policy.

---

## What we are deliberately not building

- **No policy CMS.** The markdown files in this folder are the source. Editing them is a pull
  request, which is the review trail a legal document should have.
- **No per-document acceptance.** One version number covers the Terms and the Privacy Policy
  together. Separate tracking would mean separate gates and a matrix of states for no practical
  gain.
- **No acceptance audit table.** The version and timestamp on the user row answer "did they accept,
  which version, when" — the questions that actually get asked. A full history can be added later
  if it is ever needed.
- **No forced re-read.** We do not require scrolling to the bottom before the button enables. It is
  theatre; people scroll past it. A clear checkbox and a readable document are more honest.

---

## Order of work

| Phase | What | Depends on |
|---|---|---|
| 1 | Backend: migration, version constant, `/policies`, bootstrap field, accept endpoint | — |
| 2 | Mobile: document reader + provider | 1 |
| 3 | Mobile: signup checkbox | 2 |
| 4 | Mobile: acceptance gate + router rule | 1, 2 |
| 5 | Employer portal gate | 1 |
| 6 | Footer links everywhere | 2 |

Phases 1–4 are the requirement. 5 is the one with real exposure behind it. 6 is polish.

Each phase ends green: `pytest` both suites, `ruff`, `flutter analyze`, `flutter test`, line limits.

---

## Two things to flag now

**The snapshot changes in Phase 1.** Adding `policies_accepted` to `BootstrapResponse` is a real
contract change, so the baseline gets regenerated. Mobile and backend ship together — an older app
build reading the new response will not find the field and will treat acceptance as false, which
means it gates its own users out. Worth remembering at release time.

**Existing pilot accounts will all be gated at once.** `server_default='0'` means everyone who has
already signed up sees `/accept-policies` on their next launch. That is correct behaviour, but it
will look like a surprise if nobody is expecting it — worth a heads-up to whoever is testing.
