"""Campus email normalization and server-owned role inference.

Roles are never chosen by clients — they are derived from the exact email domain
(or a development-only test-email allowlist). Use exact domain equality; never
`endswith("livingstone.edu")`, which would mis-classify `@students.livingstone.edu`.
"""

from __future__ import annotations

from app.config import settings

STUDENT_DOMAIN = 'students.livingstone.edu'
STAFF_DOMAIN = 'livingstone.edu'
ALLOWED_ROLES = frozenset({'student', 'staff', 'admin'})


def normalize_campus_email(email: str) -> str:
    """Lowercase, trim, and accept only campus domains or env-gated dev test emails."""
    normalized = email.lower().strip()
    if '@' not in normalized:
        raise ValueError(
            'Only Livingstone College email addresses are allowed '
            '(@students.livingstone.edu or @livingstone.edu)'
        )
    domain = normalized.rsplit('@', 1)[-1]
    if domain in settings.allowed_email_domain_set:
        return normalized
    if normalized in settings.dev_test_email_set and settings.dev_test_emails_permitted:
        return normalized
    raise ValueError(
        'Only Livingstone College email addresses are allowed '
        '(@students.livingstone.edu or @livingstone.edu)'
    )


def infer_role_from_email(email: str) -> str:
    """Map a normalized campus email to `student` or `staff`. Raises on unknown domains."""
    normalized = normalize_campus_email(email)
    if normalized in settings.dev_test_email_set:
        role = settings.dev_test_email_default_role
        if role not in {'student', 'staff'}:
            raise ValueError('DEV_TEST_EMAIL_DEFAULT_ROLE must be student or staff')
        return role

    domain = normalized.rsplit('@', 1)[-1]
    if domain == STUDENT_DOMAIN:
        return 'student'
    if domain == STAFF_DOMAIN:
        return 'staff'
    raise ValueError(
        'Only Livingstone College email addresses are allowed '
        '(@students.livingstone.edu or @livingstone.edu)'
    )


def sync_user_role_from_email(user, email: str) -> None:
    """Refresh `user.role` from email for non-admin accounts (bootstrap + backfill safety)."""
    if user.role == 'admin':
        return
    user.role = infer_role_from_email(email)


def normalize_campus_contact_email(email: str) -> str:
    """Official directory contacts must use a Livingstone campus address.

    Same domain rules as account emails — never publish an arbitrary external
    inbox as a verified campus contact.
    """
    return normalize_campus_email(email)
