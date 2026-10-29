"""Scholar professional-profile URL allowlist — http(s) only."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.features.scholars.schema import ScholarProfessionalProfileUpdate, ScholarProjectEntry


@pytest.mark.parametrize(
    'bad',
    [
        'javascript:alert(1)',
        'data:text/html,<script>',
        'ftp://example.com/x',
        'not a url',
        'localhost',  # no dotted host
    ],
)
def test_rejects_non_http_profile_urls(bad: str):
    with pytest.raises(ValidationError):
        ScholarProfessionalProfileUpdate(linkedin_url=bad)
    with pytest.raises(ValidationError):
        ScholarProjectEntry(name='Demo', url=bad)


def test_accepts_https_and_clears_empty():
    update = ScholarProfessionalProfileUpdate(
        linkedin_url='https://linkedin.com/in/scholar',
        handshake_url='',
    )
    assert update.linkedin_url == 'https://linkedin.com/in/scholar'
    assert update.handshake_url is None
    project = ScholarProjectEntry(name='Demo', url='http://example.com/p')
    assert project.url == 'http://example.com/p'


def test_bare_host_gets_https():
    """A scheme-less link is completed, not rejected — rejecting it failed the whole profile save."""
    update = ScholarProfessionalProfileUpdate(linkedin_url='linkedin.com/in/x')
    assert update.linkedin_url == 'https://linkedin.com/in/x'
    assert ScholarProjectEntry(name='Demo', url='github.com/me/p').url == 'https://github.com/me/p'
