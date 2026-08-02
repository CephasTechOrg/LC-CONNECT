"""LC Connect's own invite email — the only invite email ever sent (Supabase's own mailer/
templates are bypassed via `generate_link`, see `app/shared/supabase_admin.py`)."""

from __future__ import annotations

from app import email as email_service


def _capture_send(monkeypatch):
    calls: list[dict] = []

    def _fake(*, to_email, subject, text, html):
        calls.append({'to_email': to_email, 'subject': subject, 'text': text, 'html': html})

    monkeypatch.setattr(email_service, '_send_email', _fake)
    return calls


def test_send_invite_email_admin_context(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_invite_email(
        'admin@livingstone.edu',
        page_url='https://admin.example.com/accept-invite',
        code='12345678',
        context='admin',
    )
    assert len(calls) == 1
    call = calls[0]
    assert call['to_email'] == 'admin@livingstone.edu'
    assert 'invited' in call['subject'].lower()
    assert 'https://admin.example.com/accept-invite' in call['html']
    assert '12345678' in call['html']
    assert '12345678' in call['text']


def test_send_invite_email_employer_context(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_invite_email(
        'contact@acme.com',
        page_url='https://employer.example.com/accept-invite',
        code='87654321',
        context='employer',
    )
    call = calls[0]
    assert 'employer' in call['subject'].lower() or 'approved' in call['subject'].lower()
    assert 'employer partner' in call['html'].lower()
    assert '87654321' in call['html']


def test_send_invite_email_defaults_to_admin_context(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_invite_email('x@y.com', page_url='https://admin.example.com/accept-invite', code='11112222')
    assert 'admin' in calls[0]['html'].lower()


def test_send_password_reset_email(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_password_reset_email(
        'student@students.livingstone.edu',
        page_url='https://admin.example.com/reset-password',
        code='99887766',
    )
    assert len(calls) == 1
    call = calls[0]
    assert call['to_email'] == 'student@students.livingstone.edu'
    assert 'reset' in call['subject'].lower()
    assert 'https://admin.example.com/reset-password' in call['html']
    assert '99887766' in call['html']
    assert '99887766' in call['text']


def test_send_signup_confirmation_email(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_signup_confirmation_email(
        'newstudent@students.livingstone.edu',
        code='55443322',
    )
    assert len(calls) == 1
    call = calls[0]
    assert call['to_email'] == 'newstudent@students.livingstone.edu'
    assert 'confirm' in call['subject'].lower()
    assert '55443322' in call['html']
    assert '55443322' in call['text']


def test_emails_never_contain_a_magic_link(monkeypatch):
    """The whole point of the page_url change: `action_link` and the emailed code are the same
    single-use Supabase token, so clicking a magic link silently burned the code the user was
    about to type. No auth email may ever embed `/auth/v1/verify`."""
    calls = _capture_send(monkeypatch)
    email_service.send_invite_email('a@b.com', page_url='https://portal.example.com/accept-invite', code='11112222')
    email_service.send_password_reset_email('a@b.com', page_url='https://portal.example.com/reset-password', code='33334444')
    email_service.send_signup_confirmation_email('a@b.com', code='55556666')

    for call in calls:
        assert '/auth/v1/verify' not in call['html'], call['subject']
        assert '/auth/v1/verify' not in call['text'], call['subject']


def test_invite_email_without_page_url_still_sends_the_code(monkeypatch):
    """A missing portal URL must degrade to a code-only email, never render a broken button."""
    calls = _capture_send(monkeypatch)
    email_service.send_invite_email('a@b.com', page_url=None, code='99998888')
    assert '99998888' in calls[0]['html']
    assert '<a href="None"' not in calls[0]['html']
    assert 'href=""' not in calls[0]['html']
