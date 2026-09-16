"""What "complete" means for a Blueprint Bond profile.

Beta report #6 asked for the dashboard prompt to disappear once a scholar finishes. That makes the
completeness rule load-bearing: it no longer just changes a card's styling, it decides whether the
card exists. So the rule is defined server-side, in one place, and pinned here.

The rule it replaces lived on the client as
``summary.isNotEmpty && (hasResume || hasHeadshot)``. It accepted a one-character summary, accepted
a headshot with no résumé, and — the reason these tests exist — ignored
``employer_visibility_consent`` completely, so a scholar could be "complete" while remaining
invisible to every employer.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from app.features.scholars.service import (
    CURRENT_CONSENT_VERSION,
    MIN_CAREER_INTERESTS,
    MIN_SKILLS,
    MIN_SUMMARY_LENGTH,
    missing_profile_fields,
)
from app.models import ScholarProfessionalProfile


def _complete(**overrides) -> ScholarProfessionalProfile:
    """A profile that satisfies every requirement; override one field to break exactly one rule."""
    fields = {
        'summary': 'x' * MIN_SUMMARY_LENGTH,
        'headshot_path': 'scholars/u1/headshot.jpg',
        'resume_path': 'scholars/u1/resume.pdf',
        'skills': ['Python', 'SQL', 'Public speaking'][:max(MIN_SKILLS, 3)],
        'career_interests': ['Data analysis'],
        'employer_visibility_consent': True,
        'consent_version': CURRENT_CONSENT_VERSION,
        'consent_given_at': datetime(2026, 9, 1, tzinfo=UTC),
    }
    fields.update(overrides)
    return ScholarProfessionalProfile(**fields)


def test_a_fully_populated_profile_is_complete():
    assert missing_profile_fields(_complete()) == []


def test_a_brand_new_profile_reports_every_requirement():
    # What a freshly verified scholar sees: the lazily created row from `_get_or_create`.
    fresh = ScholarProfessionalProfile(
        skills=[], career_interests=[], employer_visibility_consent=False, consent_version=0
    )
    missing = missing_profile_fields(fresh)
    assert missing == [
        'summary',
        'headshot',
        'resume',
        'skills',
        'career_interests',
        'employer_visibility_consent',
    ]


@pytest.mark.parametrize(
    ('overrides', 'expected'),
    [
        ({'summary': None}, 'summary'),
        ({'summary': ''}, 'summary'),
        ({'summary': '   '}, 'summary'),
        ({'headshot_path': None}, 'headshot'),
        ({'resume_path': None}, 'resume'),
        ({'skills': []}, 'skills'),
        ({'career_interests': []}, 'career_interests'),
        ({'employer_visibility_consent': False}, 'employer_visibility_consent'),
    ],
)
def test_each_requirement_is_individually_load_bearing(overrides, expected):
    missing = missing_profile_fields(_complete(**overrides))
    assert missing == [expected], f'expected only {expected!r} outstanding, got {missing}'


def test_a_short_summary_does_not_count():
    # The old client rule accepted a single character.
    short = _complete(summary='x' * (MIN_SUMMARY_LENGTH - 1))
    assert 'summary' in missing_profile_fields(short)


def test_a_summary_is_measured_after_trimming():
    assert 'summary' in missing_profile_fields(_complete(summary=' ' * (MIN_SUMMARY_LENGTH + 10)))


def test_a_headshot_alone_no_longer_substitutes_for_a_resume():
    # The old rule was `hasResume || hasHeadshot`, so this profile used to read as complete.
    assert missing_profile_fields(_complete(resume_path=None)) == ['resume']


def test_too_few_skills_is_incomplete():
    assert 'skills' in missing_profile_fields(_complete(skills=['Python'] * (MIN_SKILLS - 1)))


def test_exactly_the_minimum_skills_is_enough():
    assert missing_profile_fields(_complete(skills=['a'] * MIN_SKILLS)) == []


def test_exactly_the_minimum_career_interests_is_enough():
    assert missing_profile_fields(_complete(career_interests=['a'] * MIN_CAREER_INTERESTS)) == []


class TestConsent:
    """Consent is what makes the rest of the profile visible, so it gates completeness."""

    def test_withheld_consent_is_incomplete(self):
        assert missing_profile_fields(_complete(employer_visibility_consent=False)) == [
            'employer_visibility_consent'
        ]

    def test_a_stale_consent_version_is_incomplete(self):
        # Bumping CURRENT_CONSENT_VERSION forces re-consent; a profile pinned to the old version
        # must stop counting as complete so the prompt returns.
        stale = _complete(consent_version=CURRENT_CONSENT_VERSION - 1)
        assert missing_profile_fields(stale) == ['employer_visibility_consent']

    def test_completeness_can_regress(self):
        """The dashboard card must be able to come back — new behaviour the old design never had.

        Before report #6 the card never disappeared, so nothing depended on the rule being
        reversible. Now that completion removes it, a revoked consent has to restore it.
        """
        profile = _complete()
        assert missing_profile_fields(profile) == []

        profile.employer_visibility_consent = False
        assert missing_profile_fields(profile) == ['employer_visibility_consent']

        profile.employer_visibility_consent = True
        assert missing_profile_fields(profile) == []


def test_missing_fields_are_ordered_the_way_a_student_would_fill_them():
    fresh = ScholarProfessionalProfile(
        skills=[], career_interests=[], employer_visibility_consent=False, consent_version=0
    )
    missing = missing_profile_fields(fresh)
    # Consent last: it is the act of publishing, and prompting for it first would be confusing.
    assert missing[-1] == 'employer_visibility_consent'
    assert missing.index('summary') < missing.index('skills')


def test_none_valued_collections_are_treated_as_empty():
    # Defensive: the columns are NOT NULL with a list default, but a detached/partially built
    # instance can still carry None, and this function must not raise on it.
    assert 'skills' in missing_profile_fields(_complete(skills=None))
    assert 'career_interests' in missing_profile_fields(_complete(career_interests=None))
