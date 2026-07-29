"""Unit tests for campus email normalization and server-owned role inference."""

from __future__ import annotations

import pytest

from app.shared import email_roles


@pytest.mark.parametrize(
    ('email', 'expected'),
    [
        ('user@students.livingstone.edu', 'student'),
        ('USER@STUDENTS.LIVINGSTONE.EDU', 'student'),
        ('  prof@livingstone.edu  ', 'staff'),
        ('advisor@livingstone.edu', 'staff'),
    ],
)
def test_infer_role_from_campus_domains(email: str, expected: str) -> None:
    assert email_roles.infer_role_from_email(email) == expected


def test_students_subdomain_is_not_staff() -> None:
    """Loose suffix matching would mis-classify students — guard with exact domains."""
    assert email_roles.infer_role_from_email('x@students.livingstone.edu') == 'student'


@pytest.mark.parametrize(
    'email',
    [
        'user@gmail.com',
        'user@evil.livingstone.edu',
        'not-an-email',
    ],
)
def test_infer_role_rejects_invalid_domains(email: str) -> None:
    with pytest.raises(ValueError):
        email_roles.infer_role_from_email(email)


def test_dev_test_email_gets_configured_role(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(email_roles.settings, 'environment', 'development')
    monkeypatch.setattr(
        email_roles.settings,
        'dev_test_emails',
        'tester@example.com,other@example.com',
    )
    monkeypatch.setattr(email_roles.settings, 'dev_test_email_default_role', 'staff')
    assert email_roles.infer_role_from_email('tester@example.com') == 'staff'


def test_dev_test_email_per_email_role_overrides_default(monkeypatch: pytest.MonkeyPatch) -> None:
    """`email:role` pins that account's role, so staff and student test accounts can coexist."""
    monkeypatch.setattr(email_roles.settings, 'environment', 'development')
    monkeypatch.setattr(
        email_roles.settings,
        'dev_test_emails',
        'prof@example.com:staff,pupil@example.com',
    )
    monkeypatch.setattr(email_roles.settings, 'dev_test_email_default_role', 'student')
    assert email_roles.infer_role_from_email('prof@example.com') == 'staff'  # pinned
    assert email_roles.infer_role_from_email('pupil@example.com') == 'student'  # default


def test_dev_test_email_rejected_outside_dev(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(email_roles.settings, 'environment', 'staging')
    monkeypatch.setattr(email_roles.settings, 'dev_test_emails', 'tester@example.com')
    with pytest.raises(ValueError):
        email_roles.infer_role_from_email('tester@example.com')


def test_sync_user_role_skips_admin() -> None:
    class _User:
        role = 'admin'

    user = _User()
    email_roles.sync_user_role_from_email(user, 'anyone@livingstone.edu')
    assert user.role == 'admin'


def test_sync_user_role_updates_non_admin() -> None:
    class _User:
        role = 'student'

    user = _User()
    email_roles.sync_user_role_from_email(user, 'dean@livingstone.edu')
    assert user.role == 'staff'
