"""The featured-activity weights have to agree across the language boundary.

The server picks the featured activity; the app keeps the same scorer as an offline fallback. If
the two drifted, the app would feature one activity while offline and another online. The
constants cannot be shared, so they are asserted against each other here.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.features.activities import featured

_DART = Path('../mobile/lib/features/activities/data/featured_ranking.dart')

_PAIRS = {
    '_wTiming': featured.W_TIMING,
    '_wScarcity': featured.W_SCARCITY,
    '_wParticipation': featured.W_PARTICIPATION,
    '_joinedPenalty': featured.JOINED_PENALTY,
    '_fullPenalty': featured.FULL_PENALTY,
    '_fillingUpRatio': featured.FILLING_UP_RATIO,
}


@pytest.mark.skipif(not _DART.exists(), reason='mobile/ not checked out')
def test_weights_match_the_app():
    source = _DART.read_text()
    for name, value in _PAIRS.items():
        match = re.search(rf'const double {name} = ([0-9.]+);', source)
        assert match, f'{name} is gone or renamed in featured_ranking.dart'
        assert float(match.group(1)) == value, name
    assert re.search(r'const int _popularThreshold = (\d+);', source).group(1) == str(featured.POPULAR_THRESHOLD)
    assert 'Duration(hours: 48)' in source and featured.STARTING_SOON.total_seconds() == 48 * 3600
