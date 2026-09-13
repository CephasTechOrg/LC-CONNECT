# LC Connect — Privacy Policy

**Version 1 · Effective: [launch date]**

What LC Connect stores about you, who can see it, who else is involved, how long we keep it, and
what you can ask us to do. This describes the app as it actually works.

---

## 1. What we store

### You give us

| Data | Why |
|---|---|
| **Campus email address** | Your identity. It is what you sign in with, and its domain decides whether you are a student or staff. |
| **Personal email address** | Where we send confirmation codes, password resets and security notices. |
| **Password** | Handled entirely by our sign-in provider. **We never see or store your password.** |
| Display name, pronouns, major, class year, location, bio, profile photo | Your profile |
| Interests, languages you speak and are learning, what you are looking for | Discovery and matching |
| Messages you send | Delivering your conversations |
| Groups, activities, connections | Running those features |
| Reports you file | Safety review |
| Staff only: position title, department, office, phone, availability | The campus directory |
| Scholars only: professional summary, skills, career interests, LinkedIn and Handshake links, **résumé**, **headshot** | Employer visibility, if you opt in |

### We generate

- Whether your email is confirmed, and whether an administrator has verified your campus identity
- Which announcements you have read
- Who you have blocked
- A device token for each device, so we can send push notifications
- Timestamps for creation and updates
- Attendance records, for the specific class that uses check-in
- A log of which employer viewed a scholar profile, and when
- Administrator action logs

### We do not collect

- **Your location.** Attendance check-in works by scanning a code that is valid for about ten
  seconds. There is no GPS and no location tracking anywhere in the app.
- **Any biometric data.** No face, fingerprint or voice data.
- **Your contacts, photo library, or calendar.**
- **Advertising or tracking identifiers.** There are no advertising or analytics trackers in
  LC Connect.

## 2. Who can see what

### Other members

By default, **any signed-in member can see your profile** — your name, photo, pronouns, major,
class year, location, bio, interests and languages.

Worth being precise, because people often assume otherwise: **you do not have to be connected to
someone for them to see your profile.** What a connection controls is messaging and group invites,
not profile viewing.

You can change this at any time:

- **Hide your profile** — you disappear from discovery and the directory.
- **Only confirmed members** — restrict your profile to people who have confirmed their email.
- **Block someone** — you and they become invisible to each other across profiles, messaging and
  discovery. **Blocking is silent; they are not told.**

Your **campus email address is never shown to other students.** Staff addresses *are* shown in the
directory, since a staff member's campus contact details are meant to be reachable.

### People you message

Anyone in a conversation with you can see what you sent. Anyone in a group can see what you post
there — treat groups as semi-public.

### Administrators

Administrators can see your account details — your name, email addresses, role, and account status.

**Nobody can read your conversations.** There is no feature anywhere in LC Connect that opens
someone's inbox — not for administrators, not for anyone.

The single exception is a message that gets reported. When you report one, a copy of that one
message is saved to the report, and that copy is all an administrator sees. Opening it requires
two-factor authentication and is logged. Everything else you have ever sent stays between you and
the person you sent it to.

Reports are not anonymous to administrators — we store who filed each one.

### Employers — scholars only, and only if you say yes

Employer visibility is **off by default**. If you turn it on, approved employer organisations can
see only:

> your display name, professional summary, skills, career interests, LinkedIn and Handshake links,
> your headshot, and your résumé.

Nothing else. That list is built by hand in the code specifically so no part of your social profile
— no bio, major, class year, interests, activities, groups or messages — can leak into it.

Your résumé and headshot are kept in private storage and served only through links that expire
after a few minutes. We record which employer viewed your profile and when, and you can ask us for
that log.

Employers agree to their own rules about how they use it — see the
[Employer Agreement](employer-agreement.md).

You can withdraw consent at any time, which stops future access. **It cannot retract what an
employer already saw or saved.**

**We do not sell your data. Not to employers, not to anyone.**

## 3. How your data is protected

- Everything travels over encrypted connections.
- Your password is held by our sign-in provider. We never receive it.
- Your login session is stored in your device's secure keystore, not in plain settings.
- Sessions are short-lived and refresh automatically; a dead session signs you out.
- Data is encrypted at rest by our database provider.
- Résumés and headshots are in private storage, reachable only by an expiring link.
- Sensitive administrator actions require two-factor authentication and are logged.
- Actions that could be abused are rate-limited.

On messages specifically: no feature exists for reading them, so the only one anyone ever sees is a
message somebody reported. What that rests on is a deliberate choice — messages are not end-to-end
encrypted, meaning they are stored in a form our servers could read rather than scrambled so that
only you hold the key. That is exactly what makes acting on a report possible: if a reported threat
could not be read, nothing could be done about it.

No system is perfectly secure. If you find a weakness, please tell us rather than use it.

## 4. Who else is involved

We use these services to run LC Connect. Each handles only what it needs to.

| Service | What it handles |
|---|---|
| **Supabase** | Sign-in and passwords, the main database, and file storage for photos, résumés and headshots |
| **Render** | Hosting for our servers |
| **Resend** | Sending our email — confirmation codes, password resets, invitations |
| **Firebase Cloud Messaging** (Google) | Delivering push notifications to your device |
| **Google Fonts** | The app downloads its typeface |

One more, because it is not obvious: when someone pastes a link into a campus post, **our server
visits that link** to fetch its title, description and preview image. That request comes from our
server, not from your device.

Our servers and data are located in the **United States**.

We do not sell personal data, and we do not use it for advertising.

## 5. How long we keep things

| Data | How long |
|---|---|
| Your account and profile | Until you delete your account |
| Messages | Until you or the other person deletes them |
| Deleted messages | Hidden immediately, permanently purged within **90 days** |
| A reported message's saved copy | **1 year** |
| Reports and moderation records | **3 years** |
| Administrator action logs | **7 years** |
| Announcement read state | While your account exists |
| Device tokens | Until the device is removed or the token stops working |
| Attendance records | While the class needs them |

Moderation records outlive a deleted account on purpose: otherwise anyone could clear their record
by deleting and signing up again. The reported message itself is purged sooner than the report,
since the evidence only matters while a case is live.

## 6. What you can ask us to do

### Download your data

You can export your data from the app at any time. The bundle includes your profile, languages and
interests, connection requests and matches, messages you sent, conversation memberships, groups you
own, activities, program memberships, your scholar profile, device tokens, blocks, notification
counts, **and both the reports you filed and the reports filed about you**.

### Delete your account

You can delete your account from the app. It asks you to confirm who you are first, because it
cannot be undone.

Deleting removes your profile details and photo, deletes your résumé and headshot, anonymises your
account record, revokes any administrator access, and transfers or removes groups you owned. Your
campus email address is released, so it can be used again.

**What deletion cannot do**, which we would rather say than let you discover later:

- **Messages you already sent stay in the other person's conversation.** You wrote to them; that
  copy is theirs.
- **Content you posted in groups you did not own may remain**, so the group's history still makes
  sense.
- **Moderation and audit records are kept** for the periods above.

### Correct something

Most of your data you can edit yourself in the app. For anything else, contact us.

### Withdraw consent

Turn off employer visibility any time in the app. Turn off push notifications in your device
settings.

## 7. Changes

If we change this policy in a way that affects you, we will raise the policy version and ask you to
read and accept it next time you open the app.

## 8. Contact

`support@livingstone.edu` — for privacy requests, support, and security reports. We aim to answer
privacy requests within **5 business days**.
