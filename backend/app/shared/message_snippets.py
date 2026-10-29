"""A message as a one-line excerpt, for every place a message is quoted rather than shown.

Reply quotes, the inbox's "reacted to …" line and reaction notifications all quote a message. One
helper rather than three slices, so no path can quote a deleted message's body (they all return
'' for one) or disagree about how long an excerpt is.
"""

from __future__ import annotations

import re

SNIPPET_CHARS = 60

_WHITESPACE = re.compile(r'\s+')


def snippet(body: str | None, *, deleted: bool = False, limit: int = SNIPPET_CHARS) -> str:
    """Whitespace collapsed to single spaces, cut at a word boundary near `limit` with an
    ellipsis. Empty for a deleted message: the original body is kept for moderation, never shown."""
    if deleted or not body:
        return ''
    text = _WHITESPACE.sub(' ', body).strip()
    if len(text) <= limit:
        return text
    cut = text[:limit].rstrip()
    space = cut.rfind(' ')
    if space >= limit // 2:
        cut = cut[:space]
    return cut.rstrip(' ,.;:') + '…'
