"""The reaction picker and the server's allowlist have to agree across the language boundary.

The server refuses any emoji outside `REACTION_ALLOWLIST` with a 422. A picker offering one the
server refuses shows a reaction that flickers on and then vanishes; one the picker leaves out is
simply unreachable. The two lists cannot be shared, so they are asserted equal here, order
included, since the picker order is the order the chips sort in.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.features.messages.reactions import REACTION_ALLOWLIST

_DART = Path('../mobile/lib/features/messages/data/reaction_choices.dart')


@pytest.mark.skipif(not _DART.exists(), reason='mobile/ not checked out')
def test_picker_offers_exactly_the_server_allowlist():
    match = re.search(r'const kReactionChoices = <String>\[(.*?)\];', _DART.read_text(), re.S)
    assert match, 'kReactionChoices is gone or renamed — the picker is now unpinned'
    picker = tuple(re.findall(r"'([^']+)'", match.group(1)))
    assert picker == REACTION_ALLOWLIST
