"""Blueprint Bond completeness rules — shared by scholars self-service and Honors admin review.

Kept outside `features/scholars/service.py` so admin approval can re-check the same definition
without a cross-feature service import.
"""

from __future__ import annotations

from app.models import ScholarProfessionalProfile

CURRENT_CONSENT_VERSION = 1
MIN_SUMMARY_LENGTH = 80
MIN_SKILLS = 3
MIN_CAREER_INTERESTS = 1

REVIEW_STATUSES = frozenset(
    {'draft', 'pending_review', 'approved', 'changes_requested', 'revoked'}
)


def missing_profile_fields(profile: ScholarProfessionalProfile) -> list[str]:
    """Which required fields are still outstanding, in fill order. Field names match the API."""
    missing: list[str] = []
    if not (profile.summary or '').strip() or len((profile.summary or '').strip()) < MIN_SUMMARY_LENGTH:
        missing.append('summary')
    if profile.headshot_path is None:
        missing.append('headshot')
    if profile.resume_path is None:
        missing.append('resume')
    if len(profile.skills or []) < MIN_SKILLS:
        missing.append('skills')
    if len(profile.career_interests or []) < MIN_CAREER_INTERESTS:
        missing.append('career_interests')
    if not profile.employer_visibility_consent or profile.consent_version < CURRENT_CONSENT_VERSION:
        missing.append('employer_visibility_consent')
    return missing
