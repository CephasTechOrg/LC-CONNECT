"""The single policy version number, and which documents are public.

Mirrors `CURRENT_CONSENT_VERSION` in the scholars service: one integer that, when raised, makes
every stored acceptance stale and re-prompts everyone. Raise it only for changes that affect a
user's rights or obligations — new data collected, a new third party, a new prohibition, a change
to retention or deletion. Typos get a new effective date and no version bump, because prompting
people for nothing trains them to tap through without reading.
"""

from __future__ import annotations

CURRENT_POLICY_VERSION = 2

# Version history — why each bump happened, so the threshold stays consistent.
#   1  Initial Terms of Service + Privacy Policy.
#   2  Removed the governing-law clause from the Terms. That deletes a *term*, not just wording,
#      so anyone who accepted v1 agreed to a document that said something this one does not —
#      which is what the threshold in this module's docstring is for. The Privacy Policy rewrite
#      that shipped alongside it (same facts, less emphasis on what is not encrypted) would not
#      have warranted a bump on its own.

# Tracked separately from `CURRENT_POLICY_VERSION`. The employer agreement and the student-facing
# terms change on their own schedules, and raising one must not force the other's users to accept
# again for no reason.
CURRENT_EMPLOYER_AGREEMENT_VERSION = 1

# Only these are served. `docs/policies/` also holds internal working documents — the coverage
# audit, the decisions register, this plan — and an allowlist is what keeps them from being
# published by a stray filename. Anything listed here must be safe to hand to the person it
# governs: the employer agreement's internal gaps analysis was moved out of it for exactly this
# reason (see `decisions-made.md`).
PUBLIC_POLICY_SLUGS: tuple[str, ...] = (
    'terms-of-service',
    'privacy-policy',
    'community-guidelines',
    'employer-agreement',
)

# The two a student must accept to use the app. The employer agreement is accepted separately, in
# the employer portal, so it is public but not part of this gate.
REQUIRED_FOR_APP: tuple[str, ...] = ('terms-of-service', 'privacy-policy')
