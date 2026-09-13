"""The single policy version number, and which documents are public.

Mirrors `CURRENT_CONSENT_VERSION` in the scholars service: one integer that, when raised, makes
every stored acceptance stale and re-prompts everyone. Raise it only for changes that affect a
user's rights or obligations — new data collected, a new third party, a new prohibition, a change
to retention or deletion. Typos get a new effective date and no version bump, because prompting
people for nothing trains them to tap through without reading.
"""

from __future__ import annotations

CURRENT_POLICY_VERSION = 1

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
