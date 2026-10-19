"""Blueprint Bond Honors decision emails — copy + outcome guard."""

from __future__ import annotations

from app.email_notices import send_scholar_profile_decision_email


def test_scholar_profile_decision_email_sends_for_known_outcomes(monkeypatch):
    sent: list[tuple] = []

    def fake_decision(to_email, **kwargs):
        sent.append((to_email, kwargs))

    monkeypatch.setattr('app.email_notices._decision_email', fake_decision)

    send_scholar_profile_decision_email(
        'scholar@students.livingstone.edu',
        outcome='changes_requested',
        review_note='Please expand the summary.',
    )
    assert len(sent) == 1
    assert sent[0][0] == 'scholar@students.livingstone.edu'
    assert sent[0][1]['review_note'] == 'Please expand the summary.'
    assert 'Updates needed' in sent[0][1]['subject']


def test_scholar_profile_decision_email_ignores_unknown_outcome(monkeypatch):
    called = False

    def fake_decision(*_a, **_k):
        nonlocal called
        called = True

    monkeypatch.setattr('app.email_notices._decision_email', fake_decision)
    send_scholar_profile_decision_email('x@y.com', outcome='draft', review_note=None)
    assert called is False
