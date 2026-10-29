"""The Blueprint Bond minimums have to agree across the language boundary.

The editor shows live counters ("42 / 80 characters", "Add at least 3") so a student can see the
rule before Save. If the app's numbers drifted from the server's, the counter would say done while
the server still listed the field as missing — the exact "stuck at 3 of 6" confusion it fixes.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.shared.scholar_profile import MIN_CAREER_INTERESTS, MIN_SKILLS, MIN_SUMMARY_LENGTH

_DART = Path('../mobile/lib/features/scholars/data/blueprint_rules.dart')


@pytest.mark.skipif(not _DART.exists(), reason='mobile/ not checked out')
@pytest.mark.parametrize(
    ('constant', 'expected'),
    [
        ('kMinSummaryChars', MIN_SUMMARY_LENGTH),
        ('kMinSkills', MIN_SKILLS),
        ('kMinCareerInterests', MIN_CAREER_INTERESTS),
    ],
)
def test_client_minimums_match_the_server(constant: str, expected: int):
    match = re.search(rf'const int {constant} = (\d+);', _DART.read_text())
    assert match, f'{constant} is gone or renamed — the editor counter is now unpinned'
    assert int(match.group(1)) == expected
