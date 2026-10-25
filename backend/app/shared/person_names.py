"""First and last name rules — one definition for the signup gate and the bootstrap that stores them.

Names arrive in Supabase signup metadata, which the client writes, so they are validated here
rather than trusted. The rules are deliberately permissive about *which* letters (accents, any
script, hyphens, apostrophes) and strict only about what cannot be a name: blank, digits, symbols,
control characters, or longer than a database column.
"""

from __future__ import annotations

import unicodedata
from collections.abc import Mapping

MAX_NAME_LENGTH = 50

# Punctuation real names use: "Mary-Jane", "O'Neil", "N’Golo", "St. John".
_NAME_PUNCTUATION = frozenset(" -'.’")

FIRST_NAME_KEY = 'first_name'
LAST_NAME_KEY = 'last_name'


def _is_name_char(char: str) -> bool:
    # Category M* covers combining accents in decomposed text ("é" typed as e + ´).
    return char.isalpha() or unicodedata.category(char).startswith('M') or char in _NAME_PUNCTUATION


def normalize_person_name(raw: object) -> str:
    """Trimmed, single-spaced name. Raises ValueError with a user-facing reason when invalid."""
    if not isinstance(raw, str):
        raise ValueError('Name is required')
    name = ' '.join(raw.split())
    if not name:
        raise ValueError('Name is required')
    if len(name) > MAX_NAME_LENGTH:
        raise ValueError(f'Name must be {MAX_NAME_LENGTH} characters or fewer')
    if not any(char.isalpha() for char in name) or not all(_is_name_char(char) for char in name):
        raise ValueError('Name can only contain letters, spaces, hyphens and apostrophes')
    return name


def names_from_metadata(metadata: object) -> tuple[str, str] | None:
    """Both names from a Supabase metadata dict, or None when either is missing or invalid.

    All or nothing: a first name with no last name is an incomplete signup, not half a name to keep.
    """
    if not isinstance(metadata, Mapping):
        return None
    try:
        return (
            normalize_person_name(metadata.get(FIRST_NAME_KEY)),
            normalize_person_name(metadata.get(LAST_NAME_KEY)),
        )
    except ValueError:
        return None
