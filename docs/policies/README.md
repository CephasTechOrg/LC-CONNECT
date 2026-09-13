# LC Connect — Policies

Drafts of the documents students and staff must accept before using LC Connect, plus the audit
that produced them.

> **Not legal advice.** These describe accurately what the system actually does, in plain language.
> They are deliberately light — LC Connect is a project built for the campus community, not an
> official College IT system, and the documents are scoped to match. All twelve open questions are
> now settled; see [`decisions-made.md`](decisions-made.md).

## The documents

| File | What it is | Who reads it |
|---|---|---|
| [`terms-of-service.md`](terms-of-service.md) | The agreement itself: who may use LC Connect, the rules, what happens when they are broken, and the College's limits of responsibility. | Accepted at signup |
| [`privacy-policy.md`](privacy-policy.md) | What data we store, who can see it, who we share it with, how long we keep it, and what a user can demand of us. | Accepted at signup |
| [`community-guidelines.md`](community-guidelines.md) | The behaviour rules in plain language, with examples. | Linked from signup and the app |
| [`feature-policy-coverage.md`](feature-policy-coverage.md) | The audit: every feature in the system mapped to the clauses it requires. Start here. | Internal |
| [`employer-agreement.md`](employer-agreement.md) | Rules for approved employer organisations using the scholar portal. | Accepted in the employer portal |
| [`decisions-made.md`](decisions-made.md) | The twelve policy questions and what was decided. | Internal |

## On naming — one correction

"Terms and Conditions" and "User Agreement" are two names for the **same document**. Picking both
would mean writing one contract twice and then having to keep the copies in step. So this set uses
**Terms of Service** as the single agreement (the name most students will recognise from other
apps), and splits out the two things that genuinely are separate documents:

- **Community Guidelines** — behaviour rules. Separate because it is the part students will actually
  read, and because it should be editable without amending a contract.
- **Privacy Policy** — data handling. Separate because it is the one document people genuinely
  expect to be able to read on its own, and because an app holding student profiles, messages and
  résumés should say plainly what it does with them. This was not in the original request; it is
  the most important of the three.

If the College prefers the label "Terms and Conditions", rename the file — the content is the same.
What matters is that there is exactly one agreement document, not two overlapping ones.

## How acceptance works

**Requirement:** a user who has not accepted cannot reach the app. Not a checkbox they can skip —
a gate.

The system already has a working precedent for versioned consent, in
[`app/models/programs.py`](../../backend/app/models/programs.py) for employer visibility:

```python
employer_visibility_consent: Mapped[bool]
consent_given_at: Mapped[datetime | None]
consent_version: Mapped[int]   # bump CURRENT_CONSENT_VERSION to force re-consent
```

The same three-field shape is the right model for policy acceptance, for the same reason: a
version number means a later policy change can require everyone to accept again, rather than
leaving users bound to a document they never saw.

Where the gate belongs — and why **not** at signup alone:

- Acceptance must be recorded **server-side, against the user row**. A checkbox that only the
  mobile client enforces is not a gate; anything holding a valid token could skip it.
- `POST /auth/bootstrap` is the natural chokepoint. It already runs on every launch and every
  login, already returns `is_verified` and `profile_completed` for the router to gate on, and is
  the one call the app cannot proceed without. Adding `policies_accepted` there means the existing
  redirect logic handles it with no new plumbing.
- The order that follows from the current router is:
  **confirm email → accept policies → onboarding → app.** Policies come before onboarding because
  onboarding is the first point where the user *creates content about themselves*.

**Employers** accept the [Employer Agreement](employer-agreement.md) in the employer portal, gated
the same way. **Administrators** need no separate agreement — they are College employees already
bound by employment terms; what they need is an internal procedure for when opening a report is
appropriate.

## Keeping these honest

The drafts describe the system **as built**, verified against the code — not as we might wish it
were. Two consequences worth stating up front:

1. **LC Connect is not end-to-end encrypted, and the policy must not say it is.** See
   [`privacy-policy.md`](privacy-policy.md) § "How your data is protected" for what is actually
   true.
2. **Profiles are not connection-gated.** Any signed-in, email-confirmed user can view any profile
   that is not hidden or blocked. Connections gate *messaging* and *group invites*, not profile
   viewing. See [`feature-policy-coverage.md`](feature-policy-coverage.md) § Discovery.

When a feature changes, update the audit first, then the affected clause. A policy that describes
behaviour the code no longer has is worse than no policy.
