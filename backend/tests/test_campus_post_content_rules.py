"""Opportunity posts require summary; body may be omitted (copied from summary)."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.features.campus_hub.schema import CampusPostCreate


def test_opportunity_requires_summary():
    with pytest.raises(ValidationError):
        CampusPostCreate(kind='opportunity', title='Intern', category='internship')


def test_opportunity_fills_body_from_summary():
    post = CampusPostCreate(
        kind='opportunity',
        title='Summer Intern',
        summary='Paid internship on campus.',
        category='internship',
    )
    assert post.body == 'Paid internship on campus.'
    assert post.summary == 'Paid internship on campus.'


def test_opportunity_keeps_explicit_body():
    post = CampusPostCreate(
        kind='opportunity',
        title='Summer Intern',
        summary='Short blurb.',
        body='Longer details for the detail screen.',
        category='internship',
    )
    assert post.body == 'Longer details for the detail screen.'


def test_announcement_still_requires_body():
    with pytest.raises(ValidationError):
        CampusPostCreate(kind='announcement', title='Hello', summary='Only summary')
