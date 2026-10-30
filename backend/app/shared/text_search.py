"""Safe substring matching for user-typed search text."""

from __future__ import annotations


def like_pattern(text: str) -> str:
    """`%text%` for an ILIKE match, with the user's own `%`, `_` and `\\` taken literally.

    Unescaped, a search for `%` or `_` matched everything and could not be narrowed, and a pattern
    made of wildcards forces the slowest scan the index can offer. Use with `escape='\\\\'`.
    """
    escaped = text.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
    return f'%{escaped}%'
