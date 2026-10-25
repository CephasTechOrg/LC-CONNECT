"""First/last name rules shared by the signup gate (Send Email hook) and bootstrap."""

from __future__ import annotations

import pytest

from app.shared.person_names import MAX_NAME_LENGTH, names_from_metadata, normalize_person_name


@pytest.mark.parametrize(
    ('raw', 'expected'),
    [
        ('  Ama ', 'Ama'),
        ('Mary   Jane', 'Mary Jane'),
        ("O'Neil", "O'Neil"),
        ('Ngozi-Adaeze', 'Ngozi-Adaeze'),
        ('José', 'José'),
        ('José', 'José'),  # é typed as e + combining accent
        ('St. John', 'St. John'),
        ('N’Golo', 'N’Golo'),
    ],
)
def test_real_names_are_kept_tidied(raw, expected):
    assert normalize_person_name(raw) == expected


@pytest.mark.parametrize(
    'raw',
    [None, '', '   ', 'R2D2', 'Ama!', '<script>', '---', "'", 'a\u0000b', 7, 'x' * (MAX_NAME_LENGTH + 1)],
)
def test_what_cannot_be_a_name_is_refused(raw):
    with pytest.raises(ValueError):
        normalize_person_name(raw)


def test_metadata_needs_both_names():
    assert names_from_metadata({'first_name': ' Ama', 'last_name': 'Mensah '}) == ('Ama', 'Mensah')
    assert names_from_metadata({'first_name': 'Ama'}) is None
    assert names_from_metadata({'first_name': 'Ama', 'last_name': '  '}) is None
    assert names_from_metadata(None) is None
    assert names_from_metadata('Ama Mensah') is None
