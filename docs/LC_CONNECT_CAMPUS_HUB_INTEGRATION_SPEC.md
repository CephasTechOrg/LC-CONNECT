# LC Connect Campus Hub & Verified Campus Identity

**Backend-first integration specification**  
**Repository reviewed:** `CephasTechOrg/LC-CONNECT` (`main`)  
**Prepared:** July 27, 2026

---

## 1. Purpose

This document defines how LC Connect should add a **Campus Hub** and a **verified campus identity system** without disrupting the working student discovery, activities, connections, real-time messaging, profile, and notification features.

The integration should deliver three outcomes:

1. Automatically distinguish students from staff using their Livingstone College email domain.
2. Give students a trusted place to find verified campus people and official information.
3. Give authorized school overseers a small web administration portal for verification and campus content management.

The implementation is intentionally backend-first and phased. It does not attempt to rebuild every campus system.

---

## 2. Executive Product Decision

### 2.1 System roles

LC Connect will use only three permission roles:

- `student`
- `staff`
- `admin`

The role controls what the account can do. It does not describe every job title on campus.

### 2.2 Campus categories

Campus categories are used for directory organization and discovery, not system authorization:

- `academic`
- `advising`
- `residential_life`
- `campus_services`

Examples:

- Professor or instructor -> `academic`
- Academic adviser -> `advising`
- Resident assistant or housing coordinator -> `residential_life`
- Registrar, financial aid, library, IT, or student services -> `campus_services`

### 2.3 Exact campus position

A campus position stores the person's real campus identity:

- Official title
- Department or office
- Office/location
- Contact information
- Verification status

A Resident Assistant remains a `student` but may have a verified `residential_life` position. A professor is normally `staff` with an `academic` position.

### 2.4 Primary user-facing feature

The first major feature is the **Campus Hub**. It contains:

1. **Updates** - official notices, deadlines, and campus alerts.
2. **Directory** - verified campus contacts organized by category.
3. **Resources** - evergreen campus information such as housing, advising, financial aid, registrar, safety, IT, and academic support.
4. **Opportunities** - scholarships, campus jobs, leadership openings, fellowships, internships, and volunteer opportunities. This can share the same content model as updates during the first release.

The Activities page remains separate. The Campus Hub may show a small activity preview or link, but it must not duplicate activity creation, joining, or attendance functionality.

---

## 3. Current Repository Baseline

The current codebase already provides most of the foundation needed for a smooth integration.

### Backend foundations already present

- FastAPI application with modular routers.
- PostgreSQL models managed through SQLAlchemy and Alembic.
- `User.role`, defaulting to `student`.
- Email verification through a six-digit OTP.
- Registration restricted to `students.livingstone.edu` and `livingstone.edu`, plus hard-coded development test emails.
- Existing `require_admin` dependency.
- Existing `/admin` endpoints for users, reports, suspensions, and activity removal.
- Existing `VerificationRequest` model.
- Profile, discovery, messaging, activities, reporting, and blocking systems.

### Mobile foundations already present

- Flutter with Riverpod and GoRouter.
- Authentication state already includes `role`.
- A single student-oriented onboarding flow.
- Five bottom navigation tabs: Home, Discover, Activities, Messages, and Profile.
- Home currently aggregates recommended students, activities, and messages that already have dedicated tabs.

### Important gaps in the current implementation

1. Registration validates the email domain but does not assign `staff`; every new user inherits the database default of `student`.
2. Onboarding requires a major, class year, and social connection preferences, so it cannot correctly onboard staff.
3. Profile completion is calculated using student-only fields.
4. `is_verified` currently represents email verification and is also used as a general profile badge. Staff title verification must be stored separately.
5. Staff messaging currently depends on a social `Match`; campus contacts should not require matching or connecting.
6. The existing admin API does not yet approve campus positions or manage official Campus Hub content.

---

## 4. Navigation and Information Architecture

### 4.1 Recommended navigation decision

Do not add a sixth bottom-navigation tab.

Repurpose the current **Home** tab into the **Campus Hub** because the current Home screen mainly duplicates information already available in Discover, Activities, and Messages.

Recommended bottom navigation:

- **Campus** - route remains `/home` initially to avoid routing churn.
- **Discover** - student discovery and matching.
- **Activities** - activity discovery, creation, joining, and attendance.
- **Messages** - social conversations and later approved campus conversations.
- **Profile** - account and profile management.

The internal route can remain `/home` for backward compatibility while the screen and tab label become `Campus` or `Campus Hub`.

### 4.2 Campus Hub overview screen

The Campus Hub overview should prioritize official and useful campus information:

1. Urgent update banner, when applicable.
2. Latest official updates.
3. Quick-access cards:
   - Directory
   - Resources
   - Opportunities
4. Important deadlines.
5. A small "Campus life" link to the existing Activities page.

### 4.3 Campus Hub subpages

- `/home/updates`
- `/home/directory`
- `/home/resources`
- `/home/opportunities`

These may be implemented as nested GoRouter routes or screens pushed from the Campus Hub overview.

---

## 5. Authentication and Role Assignment

### 5.1 Server-owned role detection

The user must never choose Student, Staff, or Admin during registration.

The backend assigns the role from the exact email domain:

```python
STUDENT_DOMAIN = "students.livingstone.edu"
STAFF_DOMAIN = "livingstone.edu"


def infer_role_from_email(email: str) -> str:
    normalized = email.strip().lower()
    domain = normalized.rsplit("@", 1)[-1]

    if domain == STUDENT_DOMAIN:
        return "student"
    if domain == STAFF_DOMAIN:
        return "staff"

    raise ValueError("Only Livingstone College email addresses are allowed")
```

Use exact equality. Do not use loose checks such as `endswith("livingstone.edu")`, which could accept an attacker-controlled subdomain.

### 5.2 Registration behavior

During registration:

1. Normalize the email.
2. Validate the exact allowed domain.
3. Infer the server-owned role.
4. Create the `User` with that role.
5. Send the OTP.
6. Do not allow the request payload to contain `role`.

Recommended change:

```python
role = infer_role_from_email(email)
user = User(
    email=email,
    password_hash=hash_password(payload.password),
    role=role,
    ...
)
```

### 5.3 Admin assignment

`admin` must never be inferred from an email domain and must never be selectable during signup.

An existing authorized administrator must manually promote an account. Every promotion or demotion should be recorded in an administrative audit log.

### 5.4 Email verification versus position verification

Keep these concepts separate:

- **Email verification:** proves control of a Livingstone College account.
- **Position verification:** confirms the exact title, department, and campus category shown in the directory.

The existing `User.is_verified` may remain the email-verification flag for the first implementation. Add a separate status to the campus-position model.

### 5.5 Development test emails

The current hard-coded non-Livingstone test-email allowlist should not be active in production.

Recommended approach:

- Move test emails into environment configuration.
- Enable them only when `ENVIRONMENT=development` or `testing`.
- Assign a configured test role, defaulting to `student`.
- Fail application startup if test-email bypasses are enabled in production.

### 5.6 Existing-user backfill

Add an Alembic data migration or controlled maintenance script:

- `@students.livingstone.edu` -> `student`
- `@livingstone.edu` -> `staff`, except accounts already explicitly marked `admin`
- Approved development test accounts -> configured role

Do not overwrite manually assigned administrators.

---

## 6. Role-Aware Onboarding

The existing `/onboarding` route can remain. The screen selects the correct onboarding experience from `AuthUser.role`.

### 6.1 Student onboarding

Preserve the current student flow with minimal changes:

1. Name, pronouns, major, and class year.
2. Bio, location, and interests.
3. Looking-for preferences and languages.

Student completion rule:

```text
display_name + major + class_year + at least one looking_for option
```

### 6.2 Staff onboarding

Create a separate staff onboarding flow:

**Step 1 - Basic profile**

- Display name
- Pronouns, optional
- Profile photo, optional
- Short bio, optional

**Step 2 - Campus position**

- Category: academic, advising, residential life, or campus services
- Official title
- Department or office
- Office/location, optional

**Step 3 - Contact and submission**

- Official email, prefilled and locked
- Phone, optional
- Office hours or availability, optional
- Contact preference
- Submit for position verification

Staff completion rule:

```text
display_name + category + official_title + department
```

### 6.3 Staff pending state

After email verification and onboarding, a staff user should not be completely locked out.

Recommended behavior:

- Staff may enter LC Connect and view the Campus Hub.
- Their position displays as `Pending verification` only to themselves.
- They are not listed in the public directory until approved.
- Their official title is not presented as verified until approved.
- They cannot publish official campus updates until given publishing permission.

This protects the campus identity system without creating a poor "blocked account" experience.

### 6.4 Student campus positions

Students may later request a campus position, such as Resident Assistant.

Their system role stays `student`. The verified position is stored separately.

---

## 7. Recommended Backend Data Model

### 7.1 `users`

Keep the existing table and constrain role values in application logic, and preferably at the database level:

```text
role: student | staff | admin
```

### 7.2 `campus_positions`

Create a separate model instead of placing staff-only fields directly in `profiles`.

Recommended fields:

```text
id                  UUID primary key
user_id             UUID foreign key -> users.id
category            academic | advising | residential_life | campus_services
official_title      string
department          string
office_location     nullable string
phone               nullable string
contact_email       string
availability        nullable text
bio                 nullable text
status              pending | verified | rejected | revoked
is_primary          boolean default true
is_active           boolean default true
verified_by_id      nullable UUID -> users.id
verified_at         nullable timestamp
review_note         nullable text
created_at          timestamp
updated_at          timestamp
```

Use a table that can support multiple positions later, but enforce one active primary position per user in the first release.

### 7.3 `campus_posts`

Use one content model for updates, deadlines, and opportunities during the first release.

```text
id                  UUID primary key
author_id           UUID -> users.id
kind                update | deadline | opportunity | alert
title               string
summary             nullable string
body                text
audience             all | students | staff
category             nullable campus category
priority             normal | important | urgent
status               draft | published | archived
publish_at           timestamp
expires_at           nullable timestamp
external_url         nullable string
created_at           timestamp
updated_at           timestamp
```

This avoids creating separate announcement and opportunity systems too early.

### 7.4 `campus_resources`

Store evergreen information in the database so the mobile application does not hard-code it.

```text
id                  UUID primary key
category            housing | advising | financial_aid | registrar | safety | it | academic_support | other
title               string
description         text
location             nullable string
hours                nullable string
contact_email        nullable string
phone                nullable string
external_url         nullable string
sort_order           integer
is_active            boolean
updated_by_id        UUID -> users.id
created_at           timestamp
updated_at           timestamp
```

### 7.5 `admin_audit_logs`

Record sensitive administrative changes:

```text
actor_id
action
target_type
target_id
before_data
after_data
created_at
```

At minimum, record role changes, position approvals/rejections, suspensions, and campus-content publishing.

---

## 8. Backend API Design

### 8.1 Authentication

```text
POST /auth/register
GET  /auth/me
```

Changes:

- `POST /auth/register` infers and stores the role.
- `GET /auth/me` continues returning the role.
- No public endpoint accepts a role change.

### 8.2 Profile and onboarding

Keep the current student profile endpoint for compatibility:

```text
PATCH /profiles/me
```

Add role-aware behavior or explicit endpoints:

```text
GET   /campus-positions/me
POST  /campus-positions/me
PATCH /campus-positions/me
```

Recommended rule:

- Student social profile fields remain under `/profiles/me`.
- Campus position fields remain under `/campus-positions/me`.
- The mobile onboarding provider coordinates the correct request based on role.

### 8.3 Campus Hub public endpoints

```text
GET /campus-hub/overview
GET /campus-hub/posts
GET /campus-hub/posts/{post_id}
GET /campus-hub/directory
GET /campus-hub/directory/{position_id}
GET /campus-hub/resources
GET /campus-hub/resources/{resource_id}
```

Suggested directory filters:

```text
category
department
query
```

Directory results must only return active, verified positions attached to active users.

Suggested post filters:

```text
kind
priority
category
```

The backend should automatically filter expired posts and enforce the current user's audience.

### 8.4 Admin endpoints

Extend the existing `/admin` router:

```text
GET  /admin/campus-positions/pending
GET  /admin/campus-positions/{position_id}
POST /admin/campus-positions/{position_id}/approve
POST /admin/campus-positions/{position_id}/reject
POST /admin/campus-positions/{position_id}/revoke

GET    /admin/campus-posts
POST   /admin/campus-posts
PATCH  /admin/campus-posts/{post_id}
POST   /admin/campus-posts/{post_id}/publish
POST   /admin/campus-posts/{post_id}/archive

GET    /admin/campus-resources
POST   /admin/campus-resources
PATCH  /admin/campus-resources/{resource_id}
```

For the first release, only admins publish official posts. Delegated staff publishing can be added later with explicit permissions.

---

## 9. Contacting Staff Without Social Matching

Staff should not appear in the social discovery card queue and should not require a connection or match.

### First-release contact actions

A verified directory profile may offer:

- Send official email
- Call, when a phone number is provided
- View office/location
- View office hours or availability

### Later direct messaging

If in-app student-to-staff messaging is added, create a separate conversation type such as `campus_contact`. Do not force it into the existing `Match` model.

Possible future design:

```text
conversation_type: social_match | campus_contact | group
```

This should be a later feature because it changes the messaging data model, authorization rules, and moderation requirements.

---

## 10. Minimal Admin Web Portal

Administrative work should use a responsive web portal. Staff continue using the Flutter application.

### First-release pages

1. **Overview**
   - Pending position verifications
   - Published/expiring updates
   - Open reports
   - Active and suspended users

2. **People & Positions**
   - Search users
   - Review staff and student campus-position requests
   - Approve, reject, or revoke positions
   - Manually promote or demote administrators
   - Suspend users

3. **Campus Content**
   - Create and manage updates, deadlines, alerts, and opportunities
   - Create and manage campus resources
   - Preview audience and expiration

4. **Reports**
   - Reuse and extend the existing report-management API

### Technology recommendation

Create a small web application, preferably under the same repository initially:

```text
lc_connect_admin_web/
```

It should call the same FastAPI backend and use the existing admin authorization dependency. The first version should stay deliberately small.

---

## 11. Flutter Integration Plan

### 11.1 Feature folder

```text
lc_connect_mobile/lib/features/campus_hub/
├── models/
│   ├── campus_post.dart
│   ├── campus_position.dart
│   └── campus_resource.dart
├── providers/
│   ├── campus_hub_provider.dart
│   ├── campus_directory_provider.dart
│   └── campus_resources_provider.dart
├── screens/
│   ├── campus_hub_screen.dart
│   ├── campus_updates_screen.dart
│   ├── campus_directory_screen.dart
│   ├── campus_position_detail_screen.dart
│   ├── campus_resources_screen.dart
│   └── campus_opportunities_screen.dart
└── widgets/
    ├── urgent_update_banner.dart
    ├── campus_quick_action.dart
    ├── campus_post_card.dart
    └── directory_contact_card.dart
```

### 11.2 Router changes

- Keep `/home` as the initial authenticated destination.
- Replace `HomeScreen` with `CampusHubScreen`, or rename the existing class after moving its social sections to their existing feature pages.
- Add nested Campus Hub routes.
- Select student or staff onboarding based on `AuthUser.role`.
- Add a pending-position banner for unapproved staff.

### 11.3 Bottom navigation changes

Change only the first tab:

```text
Home -> Campus
home icon -> school/account-balance icon
path remains /home
```

No sixth tab is needed.

### 11.4 Preserve existing features

- Discover continues handling student matching.
- Activities continues handling activities.
- Messages continues handling social-match conversations.
- Profile continues handling account settings and student social-profile information.

---

## 12. Backend-First Implementation Phases

### Phase 1 - Authentication correctness

1. Add a centralized email-domain and role helper.
2. Assign the role during registration.
3. Add tests for student, staff, invalid, mixed-case, and test emails.
4. Add the existing-user role backfill.
5. Move test-email bypasses behind development configuration.
6. Keep admin manual-only.

**Result:** every account has the correct trusted system role.

### Phase 2 - Campus position and role-aware onboarding

1. Add the `campus_positions` model and Alembic migration.
2. Add campus-position schemas and services.
3. Add `/campus-positions/me` endpoints.
4. Update profile completion logic to be role-aware.
5. Split Flutter onboarding into student and staff flows.
6. Add the staff pending-verification state.
7. Update profile badges and labels to distinguish email verification from position verification.

**Result:** staff and student campus leaders can create position records safely.

### Phase 3 - Admin verification

1. Extend `require_admin`-protected endpoints.
2. Add pending-position listing and review actions.
3. Add audit logs.
4. Build the minimal People & Positions web page.

**Result:** official titles can be approved before public display.

### Phase 4 - Campus Directory

1. Add the public verified-directory endpoint.
2. Exclude staff from social discovery.
3. Build directory list, filters, and detail screens.
4. Add email, call, office, and availability actions.

**Result:** students can find the correct verified campus contact.

### Phase 5 - Campus Hub content

1. Add `campus_posts` and `campus_resources` models.
2. Add admin CRUD and publishing endpoints.
3. Add Campus Hub public endpoints.
4. Replace the current Home experience with Campus Hub.
5. Add Updates, Resources, and Opportunities screens.
6. Connect published urgent or important posts to the existing push-notification system.

**Result:** LC Connect becomes a trusted source of official campus information.

### Phase 6 - Controlled enhancement

Only after the first release is stable:

- Delegated staff publishing permissions
- Read acknowledgements for critical updates
- Direct student-to-staff campus conversations
- Targeted audiences by residence hall, major, or class year
- Calendar export and deadline reminders

---

## 13. Migration and Rollout Safety

### 13.1 Non-breaking principles

- Do not remove or rename existing API fields until mobile clients are updated.
- Add fields and endpoints first, then update Flutter.
- Keep `/home` route stable.
- Keep student onboarding behavior unchanged during the first backend deployment.
- Deploy database migrations before code that depends on them.
- Use nullable fields and safe defaults during transitional releases.

### 13.2 Recommended deployment order

1. Database migration with backward-compatible fields and tables.
2. Backend role assignment and campus-position APIs.
3. Backend tests and staging verification.
4. Mobile role-aware onboarding.
5. Admin verification web page.
6. Directory mobile release.
7. Campus content backend and admin tools.
8. Campus Hub mobile release.

### 13.3 Feature flags

Recommended flags during staged rollout:

```text
ROLE_AWARE_ONBOARDING_ENABLED
CAMPUS_DIRECTORY_ENABLED
CAMPUS_HUB_ENABLED
STAFF_PUBLISHING_ENABLED
```

Staff publishing should remain disabled in the first release.

---

## 14. Permissions Matrix

| Capability | Student | Staff | Admin |
|---|---:|---:|---:|
| Use social discovery | Yes | No | Optional/no |
| Send social connection requests | Yes | No | No |
| Join/create activities | Yes | Yes, if desired | Yes |
| View Campus Hub | Yes | Yes | Yes |
| View verified directory | Yes | Yes | Yes |
| Request a campus position | Yes | Yes | Yes |
| Appear in directory | Only with verified position | Only with verified position | Only with verified position |
| Publish official posts in V1 | No | No | Yes |
| Approve campus positions | No | No | Yes |
| Manage users and reports | No | No | Yes |

Campus categories do not grant permissions.

---

## 15. Security Rules

1. Roles are assigned and changed only by the server.
2. Use exact normalized email-domain equality.
3. OTP verification must succeed before authenticated onboarding is completed.
4. Never trust a role value from Flutter or a public API request.
5. `admin` is manual-only.
6. Directory endpoints return only verified, active positions.
7. Staff titles remain private/pending until approved.
8. Publishing endpoints require admin authorization in V1.
9. Every sensitive administrative action is audited.
10. Development test-email bypasses are disabled in production.
11. Staff should not be included in the student-matching query.
12. Expired campus posts must not appear in normal feeds.

---

## 16. Testing Plan

### Backend tests

- Student-domain registration assigns `student`.
- Staff-domain registration assigns `staff`.
- Invalid domains are rejected.
- Case and whitespace normalization work correctly.
- Development test-email behavior is environment-gated.
- Existing admin accounts are not overwritten by role backfill.
- Student profile completion remains unchanged.
- Staff profile completion uses staff fields.
- Unverified campus positions do not appear in directory results.
- Suspended users do not appear in the directory.
- Only admins approve/reject/revoke positions.
- Only admins publish posts in V1.
- Audience and expiration filtering work correctly.

### Flutter tests

- Student users receive student onboarding.
- Staff users receive staff onboarding.
- Staff pending state appears after submission.
- Campus Hub replaces the former Home content.
- Directory filters and empty states work.
- Staff contact actions do not require a connection.
- Activities remain accessible through the dedicated Activities tab.
- Existing Discover, Messages, and Profile navigation still works.

### Migration tests

- Current users retain their profiles and relationships.
- Student accounts remain students.
- Staff-domain accounts are correctly backfilled.
- Existing admins remain admins.
- New tables and indexes are created cleanly.

---

## 17. Acceptance Criteria for the First Complete Release

The feature is complete when:

1. A new student email automatically creates a student account.
2. A new staff email automatically creates a staff account.
3. Neither user can select or manipulate their role.
4. Students and staff receive different onboarding flows.
5. Staff can submit their title, category, department, and contact details.
6. An admin can approve or reject that campus position from the web portal.
7. Only approved positions appear in the directory.
8. Students can search by Academic, Advising, Residential Life, and Campus Services.
9. Students can contact a verified person without social matching.
10. The Campus Hub shows official updates, resources, and opportunities.
11. Activities remain on the existing Activities page and are not duplicated.
12. Only admins can publish official content in V1.
13. Existing social discovery, activities, messaging, and profile functionality continues passing its tests.

---

## 18. File-Level Change Map

### Existing backend files to modify

```text
lc_connect_backend/app/schemas.py
- Centralize domain rules or import a role helper.
- Add campus-position, campus-post, and campus-resource schemas.
- Keep registration payload free of role fields.

lc_connect_backend/app/routers/auth.py
- Infer and persist role during registration.

lc_connect_backend/app/models.py
- Add CampusPosition, CampusPost, CampusResource, and AdminAuditLog.

lc_connect_backend/app/routers/profiles.py
- Make profile completion role-aware or delegate campus-position completion.

lc_connect_backend/app/routers/discovery.py
- Restrict peer discovery to student candidates.

lc_connect_backend/app/routers/admin.py
- Add position review and campus-content management endpoints.

lc_connect_backend/app/main.py
- Register campus-hub and campus-position routers.
```

### Recommended new backend files

```text
lc_connect_backend/app/domain/email_roles.py
lc_connect_backend/app/routers/campus_positions.py
lc_connect_backend/app/routers/campus_hub.py
lc_connect_backend/app/services/campus_directory_service.py
lc_connect_backend/app/services/campus_content_service.py
lc_connect_backend/alembic/versions/<revision>_add_campus_hub.py
```

The current repository keeps many schemas and services in large shared files. New feature-specific modules are recommended to prevent continued growth of `models.py`, `schemas.py`, and `services.py`; this refactor can be incremental.

### Existing Flutter files to modify

```text
lc_connect_mobile/lib/features/auth/providers/auth_provider.dart
- Continue exposing server-provided role.

lc_connect_mobile/lib/features/onboarding/screens/onboarding_screen.dart
- Route to student or staff onboarding content.

lc_connect_mobile/lib/features/onboarding/providers/onboarding_provider.dart
- Submit role-specific payloads.

lc_connect_mobile/lib/core/router/app_router.dart
- Add Campus Hub nested routes and role-aware onboarding.

lc_connect_mobile/lib/shared/widgets/nav_shell.dart
- Rename Home tab to Campus while keeping /home.

lc_connect_mobile/lib/features/home/screens/home_screen.dart
- Replace or rename as CampusHubScreen.
```

### Recommended new Flutter feature

```text
lc_connect_mobile/lib/features/campus_hub/
```

### New admin web application

```text
lc_connect_admin_web/
```

---

## 19. Explicitly Out of Scope for This Phase

Do not add these to the first release:

- Full student-information-system integration
- Grades, course schedules, or confidential education records
- Emergency dispatch functionality
- Direct student-to-staff in-app messaging
- Complex staff publishing delegation
- Residence-hall-specific targeting
- Full appointment booking
- Replacing the existing Activities system
- Replacing email, LMS, registrar, or financial-aid platforms

These may be evaluated after Campus Hub adoption and usage are proven.

---

## 20. Final Recommended Build Order

1. Correct automatic role assignment.
2. Add campus-position storage.
3. Add role-aware onboarding.
4. Add admin position approval.
5. Launch the verified Campus Directory.
6. Add official posts and campus resources.
7. Replace the current Home content with the Campus Hub.
8. Connect important posts to push notifications.
9. Add opportunities using the existing campus-post model.
10. Consider staff messaging and delegated publishing only after the first release is stable.

This sequence makes LC Connect more valuable at every stage while preserving its current working systems.
