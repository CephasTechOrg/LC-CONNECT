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
        action_link='https://x.supabase.co/verify?token=abc',
        code='12345678',
        context='admin',
    )
    assert len(calls) == 1
    call = calls[0]
    assert call['to_email'] == 'admin@livingstone.edu'
    assert 'invited' in call['subject'].lower()
    assert 'https://x.supabase.co/verify?token=abc' in call['html']
    assert '12345678' in call['html']
    assert '12345678' in call['text']


def test_send_invite_email_employer_context(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_invite_email(
        'contact@acme.com',
        action_link='https://x.supabase.co/verify?token=def',
        code='87654321',
        context='employer',
    )
    call = calls[0]
    assert 'employer' in call['subject'].lower() or 'approved' in call['subject'].lower()
    assert 'employer partner' in call['html'].lower()
    assert '87654321' in call['html']


def test_send_invite_email_defaults_to_admin_context(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_invite_email('x@y.com', action_link='https://x.supabase.co/verify?token=g', code='11112222')
    assert 'admin' in calls[0]['html'].lower()


def test_send_password_reset_email(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_password_reset_email(
        'student@students.livingstone.edu',
        action_link='https://x.supabase.co/verify?token=recovery123',
        code='99887766',
    )
    assert len(calls) == 1
    call = calls[0]
    assert call['to_email'] == 'student@students.livingstone.edu'
    assert 'reset' in call['subject'].lower()
    assert 'https://x.supabase.co/verify?token=recovery123' in call['html']
    assert '99887766' in call['html']
    assert '99887766' in call['text']


def test_send_signup_confirmation_email(monkeypatch):
    calls = _capture_send(monkeypatch)
    email_service.send_signup_confirmation_email(
        'newstudent@students.livingstone.edu',
        action_link='https://x.supabase.co/verify?token=signup123',
        code='55443322',
    )
    assert len(calls) == 1
    call = calls[0]
    assert call['to_email'] == 'newstudent@students.livingstone.edu'
    assert 'confirm' in call['subject'].lower()
    assert 'https://x.supabase.co/verify?token=signup123' in call['html']
    assert '55443322' in call['html']
    assert '55443322' in call['text']
