# Policy decisions — settled

The twelve open questions, and what was decided. Replaces the earlier `open-decisions.md` register.

**Framing that shaped several of these:** LC Connect is a project built for the Livingstone College
campus community, not an official College IT system. So the documents lean on "we" and
"administrators" rather than invoking the College's name, and mention Livingstone only where it
genuinely matters — eligibility, and referring conduct matters to the College's own process.

---

| # | Question | Decided | Where it landed |
|---|---|---|---|
| 1 | Minimum age / under-18 acceptance | **Dropped.** No age gate, no minimum-age clause, no date of birth collected. | Removed from all docs |
| 2 | FERPA and attendance records | **Dropped.** Check-in is for one honors class, not College-wide attendance tracking. Treated as an ordinary app feature. | `privacy-policy.md` § 1, § 5 |
| 3 | Governing law and venue | **Kept minimal.** One sentence: built and operated in North Carolina, read under NC law, contact us first. No arbitration clause, no venue mechanics. | `terms-of-service.md` § 10 |
| 4 | Moderation retention | **As recommended.** Reported message copy 1 year · reports 3 years · admin logs 7 years. | `privacy-policy.md` § 5 |
| 5 | Separate employer agreement | **Yes.** Written. Admins still need no separate contract — they are covered by employment terms. | `employer-agreement.md` |
| 6 | Hosting region | **"United States."** Broad rather than naming a specific region, so it does not go stale if hosting moves. | `privacy-policy.md` § 4 |
| 7 | Contact addresses | **One:** `support@livingstone.edu`, for support, conduct, privacy and security. | All docs |
| 8 | Response time | **5 business days**, for privacy requests only. Nothing promised for general support. | `terms-of-service.md` § 12, `privacy-policy.md` § 8 |
| 9 | Campus email belonging to you | **Overruled my recommendation — and rightly.** A student has one campus address, the campus is small, and administrators check identity against campus email when granting the verified badge. So it is both enforceable in practice and worth stating. Now an explicit thing users confirm at signup. | `terms-of-service.md` § 1, `community-guidelines.md` |
| 10 | Personal email belonging to you | **Explicit attestation added.** Controlling the inbox proves it is yours, but users now actively confirm it — with the reason: it is where password resets go, so someone else's address is a way into your account. | `terms-of-service.md` § 1 |
| 11 | Proactive message reading | **Not reserved.** Administrators see only reported messages. The narrow right the code actually implements is the one the policy claims. | `privacy-policy.md` § 2, § 3 |
| 12 | Version bump threshold | **Substantive changes only** — new data, new third party, new prohibition, changed retention or deletion. Typos get a new date, no re-prompt. | `terms-of-service.md` § 11 |

---

## Why #9 and #10 were worth the change

These two came out better than what I proposed, and the reason is worth keeping.

I had recommended leaving both alone on the grounds that neither is *technically* enforceable — the
app cannot tell whether a campus address is yours, and a second confirm-your-inbox step would only
add friction.

That reasoning was too narrow. A term does not need a technical control behind it to do work:

- It sets the expectation, so nobody can claim they did not know.
- It gives a clean basis for suspending an account when it does happen.
- On a small campus with administrator identity checks, discovery is genuinely likely — the social
  enforcement is real even though the technical enforcement is not.

So both are now things a user actively confirms at signup, phrased with the reason attached rather
than as bare rules. "Putting someone else's address there means handing them a way into your
account" is more likely to land than "you must provide accurate information."

## Still open

Only one, and it is not blocking:

**Is `support@livingstone.edu` a live inbox?** It is published in all four documents as the single
contact address. If nothing reads it yet, a privacy request or a security report has nowhere to
land, and § 8's five-day commitment cannot be met. Worth pointing it at something real — even a
forward to a personal address — before the documents go in front of students.
