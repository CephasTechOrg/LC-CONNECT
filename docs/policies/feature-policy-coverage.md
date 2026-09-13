# Feature → policy coverage audit

Every feature in LC Connect, what it actually does, and the clause it therefore requires. Verified
against the code, not against intent. **TOS** = Terms of Service, **PRIV** = Privacy Policy,
**CG** = Community Guidelines.

The system has **18 API areas** and **36 database tables**. Everything below is grounded in a named
file so a reviewer can check the claim.

---

## 1. Accounts and identity

**What it does.** Two addresses per account, with different jobs. The **campus address**
(`@students.livingstone.edu` or `@livingstone.edu`) is the identity — it is what you sign in with,
and the domain alone decides whether you are a student or staff
(`shared/email_roles.py: infer_role_from_email`). The **personal address** is a delivery inbox: every
code we send goes there (`features/auth/email_hook.py: _resolve_delivery_email`).

**The part that needs saying plainly.** Confirming your code proves you control the *personal*
inbox. Nothing is ever sent to the campus address, so **holding a campus address is asserted, not
proven**. That is exactly why a separate admin-granted `campus_verified` badge exists.

| Clause needed | Doc |
|---|---|
| You must be a current Livingstone College student or employee; accounts are personal and not transferable | TOS |
| You may not sign up using a campus address that is not yours | TOS |
| Both addresses are stored; the personal one receives all codes and notices | PRIV |
| Your role (student/staff) is derived from your email domain and is not self-selected | TOS |
| The blue check means an administrator confirmed your campus identity; it is not automatic | TOS |
| Users confirm at signup that the campus address is theirs — enforced socially (small campus, admin identity checks) rather than technically | TOS |

---

## 2. Profiles

**What it does.** Display name, pronouns, major, class year, location, bio, avatar, interests,
languages spoken and learning, and what you are looking for (`models/core.py: Profile`).

**Visibility — correcting a common assumption.** `shared/policies.py: assert_profile_visible`
hides a profile only when:
1. the owner set it hidden, **or**
2. the owner restricted it to email-confirmed viewers and you are not confirmed, **or**
3. either of you has blocked the other.

**A connection is not required to view a profile.** Any signed-in, email-confirmed user can see any
profile that is not hidden or blocked. What connections gate is messaging and group invites.

| Clause needed | Doc |
|---|---|
| Your profile is visible to other signed-in members of the campus community by default | PRIV |
| You control: hide profile, restrict to confirmed users, and per-field content | PRIV |
| Staff profiles publish the staff member's campus email as contact info; student emails are never shown to other users (`shared/serializers.py`) | PRIV |
| Do not impersonate anyone, or put someone else's photo or details in your profile | CG |
| Do not use the bio or display name for advertising, solicitation, or abuse | CG |

---

## 3. Discovery and connections

**What it does.** A card feed of other **students only** (`features/discovery/router.py` filters
`role == 'student'`), excluding anyone hidden, blocked, or with an incomplete profile. You send a
connection request; on acceptance a `Match` row is created.

Staff and admins are deliberately excluded from student social matching
(`dependencies.py: require_verified_connect_student`).

| Clause needed | Doc |
|---|---|
| Discovery shows students only; staff cannot participate in social matching | TOS |
| You appear in discovery only once your profile is complete and not hidden | PRIV |
| Connection requests are capped per day (abuse limit) | TOS |
| Do not send connection requests for solicitation, spam, or harassment | CG |
| Declining or blocking is always available and never notified to the other person | CG |

---

## 4. Messaging

**What it does.** Direct messages are keyed on `match_id` — **an accepted connection is required**
between students (`features/messages/router.py`). Separately, staff holding an **admin-verified
campus position** may message any active user without a connection
(`shared/policies.py: can_message_as_staff`), and that channel closes automatically for both sides
if the position is revoked. Group conversations exist for group members. Real-time delivery is over
a WebSocket; messages are also stored.

**Deletion.** Deleting a message hides it immediately, and the row and its body are hard-purged
after a retention window (default **90 days**, `MESSAGE_SOFT_DELETE_RETENTION_DAYS`, via
`scripts/purge_soft_deleted_messages.py`).

| Clause needed | Doc |
|---|---|
| Students can only message people they are connected to | TOS |
| Verified staff may contact you without a connection; you may block them | TOS + PRIV |
| **Messages are stored on our servers and are not end-to-end encrypted** | PRIV |
| Administrator access to messages is limited to the snapshot saved on a report — there is no endpoint that browses conversations | PRIV |
| Deleting a message hides it at once and it is permanently purged within 90 days | PRIV |
| Prohibited: harassment, threats, hate speech, sexual content, sexual advances toward minors, profanity directed at a person, doxxing, spam, scams, sharing another person's messages without consent | CG |
| Message send rate is limited | TOS |

---

## 5. Groups

**What it does.** Create and join groups, with a hard cap on members (`GROUP_MAX_MEMBERS`, default
500). Invites require an **accepted connection** with the invitee
(`features/groups/service.py:239`). Owners moderate their own groups; deleting your account
reassigns or deletes groups you own (`features/account/service.py`).

| Clause needed | Doc |
|---|---|
| You may only invite people you are connected to | TOS |
| Group owners are responsible for content in their group and must act on reports | TOS + CG |
| Group content is visible to all members; treat it as semi-public | PRIV |
| If you delete your account, groups you own are transferred or removed | PRIV |
| Group creation and invites are rate-limited | TOS |

---

## 6. Campus Hub — announcements, opportunities, resources

**What it does.** Announcements and opportunities published by admins, and by verified staff when
`STAFF_PUBLISHING_ENABLED` is on. Urgent alerts are admin-only. Audience-scoped: `all`, `students`,
`staff` (`features/campus_hub/content_visibility.py`). Staff can read staff-audience posts only
while their position is verified. Some posts are restricted to a program's members.

A new account sees the **whole back catalogue** (there is no join-date cutoff), but only
announcements published **since they joined** count as unread.

| Clause needed | Doc |
|---|---|
| Announcements are official College communications; you are responsible for reading them | TOS |
| Opportunities are posted by the College and approved partners — the College does not guarantee any opportunity, employer, or outcome | TOS |
| Read receipts are recorded per user per announcement (`campus_post_reads`) | PRIV |
| Staff publishing requires a verified position; misuse can revoke it | TOS |

---

## 7. Campus directory and staff positions

**What it does.** Staff submit a campus position (category, title, department, office, phone,
availability). It is `pending` until an admin approves it, and approval is what unlocks staff
publishing, staff messaging, and staff-audience reading. Contact details are published in the
directory.

| Clause needed | Doc |
|---|---|
| Staff position details you submit are published to the campus community once approved | PRIV |
| You must not submit a false title, department, or role | TOS |
| A position can be revoked, which removes the associated abilities | TOS |

---

## 8. Activities

**What it does.** Create activities, join as a participant, view the roster (with each
participant's display name, avatar, and campus-verified badge). Admins can remove an activity.

| Clause needed | Doc |
|---|---|
| Joining an activity shows your name and photo to other participants | PRIV |
| Activities you create or join are listed in your data export | PRIV |
| The College does not organise, supervise, or insure user-created activities — meeting anyone in person is at your own risk | TOS |
| Do not create activities that are unsafe, discriminatory, or a front for solicitation | CG |

The in-person-safety clause matters more than it looks: this is the feature most likely to lead to
strangers meeting offline.

---

## 9. Blueprint Bond — scholars and employers

**What it does.** The most privacy-sensitive area. Presidential Scholars build a professional
profile (summary, skills, career interests, LinkedIn, Handshake, **résumé**, **headshot**).
Approved employer organisations can view it through the employer portal.

Protections already in place, and worth citing in the policy because they are unusually strong:
- Visibility requires **explicit, versioned consent** (`employer_visibility_consent`,
  `consent_given_at`, `consent_version`) — off by default, and bumping the version forces
  re-consent.
- Employers see a **hand-built** view (`features/employers/schema.py: EmployerScholarView`) that
  deliberately never derives from the social profile, so no social field can leak: no bio, major,
  class year, interests, activities, groups, or messages.
- Résumés and headshots live in a **private** bucket; every read is a short-lived signed URL
  (`SCHOLAR_SIGNED_URL_EXPIRES_SECONDS`, default 300s).
- Employer views are logged (`employer_profile_views`).

| Clause needed | Doc |
|---|---|
| Employer visibility is opt-in, off by default, and withdrawable at any time | PRIV |
| Exactly which fields an employer can see, listed explicitly | PRIV |
| We log which employer viewed your profile and when; you may request that log | PRIV |
| Your résumé and headshot are stored privately and served only via expiring links | PRIV |
| Withdrawing consent stops future views but cannot retract what an employer already saw or saved | PRIV |
| We do not sell your data to employers or anyone else | PRIV |
| Employers agree to use scholar data only for recruitment | [`employer-agreement.md`](employer-agreement.md) |

---

## 10. Honors attendance

**What it does.** Rotating signed QR codes for class check-in, with present/late windows and an
audit log. Off by default (`HONORS_ATTENDANCE_ENABLED`).

**Privacy-positive fact worth stating:** there is **no location tracking and no biometrics** — I
checked. Check-in requires only scanning a code that is valid for ~10 seconds.

| Clause needed | Doc |
|---|---|
| Attendance records are academic records shared with the program instructor and the College | PRIV |
| Attendance uses a scanned code only — we do not collect your location or any biometric data | PRIV |
| Do not share, photograph, or relay QR codes to mark someone else present | TOS + CG |
| Corrections are made by an instructor and are audit-logged | PRIV |

**Decided:** treated as an ordinary app feature. Check-in serves one honors class, not College-wide attendance tracking, so it is not being used as an institutional academic record. Records are kept while the class needs them.

---

## 11. Notifications and push

**What it does.** In-app notifications, plus push via Firebase Cloud Messaging. Device tokens are
stored per device (`device_tokens`: token, platform). Push is cleanly disabled when Firebase is not
configured.

| Clause needed | Doc |
|---|---|
| We store a device token per device to deliver push; you can turn push off in your OS settings | PRIV |
| Push notification content passes through Google's Firebase service | PRIV |
| Some notices are operational (suspension, security) and cannot be turned off | TOS |

---

## 12. Safety — blocking, reporting, suspension, appeals

**What it does.** Block a user (mutual invisibility, enforced in profiles, messaging and
discovery). Report a user, message, group or post with a reason. Admins review reports and can
suspend an account. A suspended user keeps their session so they can **appeal**, and the appeal is
reviewed and resolved or dismissed by an admin. Reactivation is possible.

| Clause needed | Doc |
|---|---|
| What gets you suspended, stated concretely | TOS + CG |
| Reports are reviewed by College administrators, who see a snapshot of the reported message (`ReportRead.message_body`, captured at report time and surviving deletion) | PRIV |
| Opening a report requires MFA and is audit-logged as `report.view` | PRIV |
| Reporting is not anonymous to administrators (`reports.reporter_id` is stored) | PRIV |
| You will be told your account is suspended and can appeal in the app | TOS |
| Knowingly false reports are themselves a violation | CG |
| Blocking is silent — the other person is not told | PRIV |

This is the due-process section. It is worth being generous here: a clear appeal path is both fairer
and easier to defend.

---

## 13. Administration

**What it does.** Admins are invited by existing admins, hold scoped memberships, and require
**MFA** for sensitive actions (`require_admin_aal2`). They can list users, suspend and reactivate,
grant and revoke campus verification, review reports and appeals, approve positions, publish
content, approve employer organisations and opportunities, and manage program membership. Actions
are written to `admin_audit_logs`.

| Clause needed | Doc |
|---|---|
| Named categories of College staff can access your account data for support, safety and moderation | PRIV |
| Administrator actions are logged | PRIV |
| Administrators require multi-factor authentication | PRIV |
| Admin access is granted by invitation and can be revoked | Internal procedure — no separate contract; admins are covered by employment terms |

---

## 14. Data rights — export and deletion

**What it does.** Already built, and stronger than most apps this size.

- **Export** (`features/account/export.py`) returns a versioned JSON bundle: profile, languages,
  interests, connection requests, matches, messages sent, conversation memberships, groups owned,
  activities, program memberships, scholar profile, device tokens, blocks, notification counts,
  **reports you filed and reports about you**.
- **Deletion** (`features/account/service.py: delete_account`) wipes profile fields, deletes the
  avatar and scholar files, anonymises the user row to `deleted+<id>@deleted.invalid`, revokes admin
  memberships, reassigns or deletes owned groups, sets `is_active=False` and `status='deleted'`,
  disconnects live sockets, and deletes the Supabase auth user. It is **step-up protected**.

| Clause needed | Doc |
|---|---|
| You can download your data at any time, and what the bundle contains | PRIV |
| You can delete your account, and exactly what deletion does | PRIV |
| What deletion does **not** remove: messages already delivered to other people's threads, content in groups you did not own, and moderation and audit records kept for safety | PRIV |
| Your email address is freed on deletion, so the address can be reused | PRIV |
| Retention after deletion: reported-message copy 1 year · reports 3 years · admin logs 7 years | PRIV |

Being specific about the limits of deletion is the honest move, and it is the clause most often
fudged. Our own export proves messages sit in other people's threads too.

---

## 15. Third parties and where data actually goes

| Service | What it handles | Verified in |
|---|---|---|
| **Supabase** | Authentication, the Postgres database, and file storage (avatars, résumés, headshots) | `config.py`, `shared/supabase_admin.py` |
| **Render** | Hosting for the API and both web portals | `render.yaml` |
| **Resend** | Sends all our email: confirmation codes, password resets, invites | `app/email.py` |
| **Firebase Cloud Messaging** (Google) | Push notification delivery | `features/notifications/push.py` |
| **Link previews** | Our server fetches the title, description and image of any URL pasted into a campus post | `shared/link_preview.py` |
| **Google Fonts** | The mobile app loads its typeface at runtime | `google_fonts` package |

| Clause needed | Doc |
|---|---|
| Name each processor and what it handles | PRIV |
| We do not sell personal data or use it for advertising | PRIV |
| Data is stored in the United States (stated broadly, so it does not go stale if hosting moves) | PRIV |

---

## 16. Security — what is true and what is not

**Verified by inspection:**
- Transport is HTTPS/TLS; the real-time socket upgrades to WSS.
- Passwords are handled entirely by Supabase Auth — we never see or store one.
- Refresh tokens are held in the device keystore, not plaintext preferences
  (`core/storage/secure_session_storage.dart`).
- Access tokens are short-lived and refreshed once per 401, then the session is dropped.
- Suspicious-volume actions are rate-limited across roughly a dozen endpoints.
- Scholar files are private, served only by expiring signed URL.
- Admin actions require MFA and are audit-logged.

**Not true, and must not be claimed:**
- **There is no end-to-end encryption.** Message bodies, profiles and bios are stored as ordinary
  readable columns in Postgres. I searched for application-level encryption of user content and
  there is none. Data is encrypted *in transit* and *at rest by the database provider*, which is
  the normal and reasonable standard — but it means **we can read message content**, and so can an
  administrator investigating a report.
  End-to-end would mean only the two participants hold the keys and we could not read messages even
  if compelled. Claiming it while holding readable data would be a false statement about a security
  property, the kind regulators treat as a deceptive practice. The policy says the true thing
  instead.

| Clause needed | Doc |
|---|---|
| Describe the real protections in plain language | PRIV |
| State clearly that messages are not end-to-end encrypted, and equally clearly that admin access is limited to reported snapshots behind MFA | PRIV |
| No system is perfectly secure; tell us about vulnerabilities rather than exploiting them | TOS |
| Do not attempt to access another account, scrape the directory, or probe the API | TOS |

---

## 17. Clauses every agreement needs, that no feature implies

| Clause | Doc |
|---|---|
| The service is provided as-is, without warranty | TOS |
| Limitation of liability | TOS |
| The College may change or discontinue features | TOS |
| How we notify you of policy changes, and that continuing to use the app means accepting them | TOS |
| Re-acceptance is required when the policy version changes | TOS |
| You keep ownership of what you post, and grant the College a licence to display it in the app | TOS |
| We may remove content that violates these rules | TOS |
| Built and operated in North Carolina, read under NC law; contact us first. No arbitration clause | TOS |
| Who to contact, and how fast we aim to respond | TOS + PRIV |
| Effective date and version number on every document | all |

---

## Decisions

All twelve settled — see [`decisions-made.md`](decisions-made.md). The only item
still outstanding is operational, not legal: pointing `support@livingstone.edu` at an inbox
somebody actually reads, since it is the single contact address in all four documents.
