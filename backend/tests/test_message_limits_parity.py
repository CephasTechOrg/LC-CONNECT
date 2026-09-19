"""The message body cap has to agree across the language boundary.

The server rejects an over-long body on every path — REST send, WebSocket send, and edit. A client
that lets a longer one be typed therefore produces a message that can never be delivered: it goes
out optimistically, is rejected, and settles as a failed bubble whose Retry can never succeed. The
two constants cannot be shared, so they are asserted against each other here — the one place a
drift would otherwise be invisible until a user pasted something long.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.shared.message_limits import MAX_BODY_CHARS

_DART = Path('../mobile/lib/features/messages/data/message_limits.dart')


@pytest.mark.skipif(not _DART.exists(), reason='mobile/ not checked out')
def test_client_cap_does_not_exceed_the_server_cap():
    match = re.search(r'const int kMaxMessageChars = (\d+);', _DART.read_text())
    assert match, 'kMaxMessageChars is gone or renamed — the composer cap is now unpinned'
    assert int(match.group(1)) == MAX_BODY_CHARS


@pytest.mark.skipif(not _DART.exists(), reason='mobile/ not checked out')
def test_both_client_inputs_enforce_the_cap():
    """The composer and the edit sheet are the only two places a body is typed."""
    composer = Path('../mobile/lib/features/messages/widgets/chat_input.dart').read_text()
    assert 'LengthLimitingTextInputFormatter(kMaxMessageChars)' in composer

    edit_sheet = Path('../mobile/lib/features/messages/widgets/chat_reactions.dart').read_text()
    assert 'maxLength: kMaxMessageChars' in edit_sheet
