"""Auth guard tests — verified-student, active/suspended, and admin-aal2 logic.

DB-free: the pure dependency functions are called directly with lightweight fake
users, and route wiring is checked via FastAPI dependency overrides (the guard
rejects before the endpoint body runs, so no database is touched).
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import (
    AuthContext,
    _ensure_active,
    get_auth_context,
    require_admin,
    require_admin_aal2,
    require_email_confirmed_user,
    require_verified_connect_student,
)
from app.main import app
from app.shared.account_status import ACCOUNT_INACTIVE_DETAIL, ACCOUNT_SUSPENDED_DETAIL


def _user(**overrides):
    """A stand-in User with just the attributes the guards read."""
    base = {"is_verified": True, "is_active": True, "status": "active", "role": "student"}
    base.update(overrides)
    return SimpleNamespace(**base)


async def _dummy_db():
    # Overrides get_db so no real database session is ever created in these tests.
    yield None


@pytest.fixture(autouse=True)
def _clear_overrides():
    yield
    app.dependency_overrides.clear()


# ── Unit: require_email_confirmed_user ────────────────────────────────────────

async def test_email_confirmed_user_passes():
    user = _user(is_verified=True)
    assert await require_email_confirmed_user(user) is user


async def test_email_confirmed_allows_verified_staff():
    """Name hazard regression: this gate is email confirmation, not student-only."""
    staff = _user(is_verified=True, role="staff")
    assert await require_email_confirmed_user(staff) is staff


async def test_unverified_user_is_forbidden():
    with pytest.raises(HTTPException) as exc:
        await require_email_confirmed_user(_user(is_verified=False))
    assert exc.value.status_code == 403
    assert exc.value.detail == "Verified account required"


async def test_require_verified_connect_student_blocks_staff():
    with pytest.raises(HTTPException) as exc:
        await require_verified_connect_student(_user(is_verified=True, role="staff"))
    assert exc.value.status_code == 403
    assert "student" in str(exc.value.detail).lower()


async def test_require_verified_connect_student_allows_student():
    student = _user(is_verified=True, role="student")
    assert await require_verified_connect_student(student) is student


# ── Unit: _ensure_active (authenticated + active) ─────────────────────────────

def test_active_user_passes():
    user = _user()
    assert _ensure_active(user) is user


@pytest.mark.parametrize(
    'overrides,expected_status,expected_detail',
    [
        ({'status': 'suspended'}, 403, ACCOUNT_SUSPENDED_DETAIL),
        ({'is_active': False}, 401, ACCOUNT_INACTIVE_DETAIL),
    ],
)
def test_inactive_or_suspended_is_rejected(overrides, expected_status, expected_detail):
    with pytest.raises(HTTPException) as exc:
        _ensure_active(_user(**overrides))
    assert exc.value.status_code == expected_status
    assert exc.value.detail == expected_detail


def test_missing_user_is_unauthorized():
    with pytest.raises(HTTPException) as exc:
        _ensure_active(None)
    assert exc.value.status_code == 401


# ── Unit: admin guards ────────────────────────────────────────────────────────

async def test_require_admin_allows_admin():
    admin = _user(role="admin")
    assert await require_admin(admin) is admin


async def test_require_admin_blocks_student():
    with pytest.raises(HTTPException) as exc:
        await require_admin(_user(role="student"))
    assert exc.value.status_code == 403


async def test_admin_aal2_allows_admin_with_mfa():
    ctx = AuthContext(user=_user(role="admin"), claims=SimpleNamespace(aal="aal2"))
    assert await require_admin_aal2(ctx) is ctx.user


@pytest.mark.parametrize(
    "ctx",
    [
        # non-admin, even with MFA
        AuthContext(user=SimpleNamespace(role="student"), claims=SimpleNamespace(aal="aal2")),
        # admin but only aal1 (no MFA) — the sole remaining way to fail this gate now that
        # the legacy non-Supabase path is gone and every context carries real claims
        AuthContext(user=SimpleNamespace(role="admin"), claims=SimpleNamespace(aal="aal1")),
    ],
)
async def test_admin_aal2_rejects(ctx):
    with pytest.raises(HTTPException) as exc:
        await require_admin_aal2(ctx)
    assert exc.value.status_code == 403


# ── Integration: guards are actually wired onto the student routes ────────────

PROTECTED_GET_ROUTES = [
    "/api/v1/profiles/me",
    "/api/v1/discovery/cards",
    "/api/v1/connections/incoming",
    "/api/v1/connections/outgoing",
    "/api/v1/connections/matches",
    "/api/v1/messages/threads",
    "/api/v1/activities",
    # Campus Hub — the content a brand-new account is most likely to reach for. The mobile
    # router also keeps an unverified user on /verify-email, but that is a UX gate, not a
    # security boundary: these must refuse the request on their own.
    "/api/v1/campus-hub/overview",
    "/api/v1/campus-hub/posts",
    "/api/v1/campus-hub/announcements/unread-count",
    "/api/v1/campus-hub/directory",
    "/api/v1/campus-hub/students",
    "/api/v1/campus-hub/resources",
]


@pytest.mark.parametrize("path", PROTECTED_GET_ROUTES)
def test_unverified_user_gets_403_on_protected_routes(path):
    app.dependency_overrides[get_auth_context] = lambda: AuthContext(
        user=_user(is_verified=False), claims=SimpleNamespace(aal="aal1")
    )
    app.dependency_overrides[get_db] = _dummy_db
    client = TestClient(app)
    response = client.get(path)
    assert response.status_code == 403, f"{path} must require a verified (email-confirmed) user"


def test_missing_token_gets_401_on_protected_route():
    # No auth override: the real get_auth_context runs and rejects the missing token.
    app.dependency_overrides[get_db] = _dummy_db
    client = TestClient(app)
    response = client.get("/api/v1/discovery/cards")
    assert response.status_code == 401


# ── The onboarding boundary: what a confirmed-but-not-onboarded account can do ──

async def test_email_confirmation_not_onboarding_is_what_unlocks_content():
    """Reading Campus Hub requires a *confirmed email*, not a finished profile.

    This is deliberate and worth pinning down, because the two are easy to conflate. The trust
    boundary is the campus address: confirming it proves the person holds an @livingstone address,
    which is what earns access to announcements and opportunities. Onboarding collects major, class
    year and interests — that makes someone *useful to others in discovery*, and withholding
    announcements until they fill it in would gate community news on an unrelated errand.

    So `require_verified_user` intentionally does not look at `profile_completed`. If that ever
    changes, it should be a decision, not a drive-by edit — hence this test.
    """
    onboarded = await require_email_confirmed_user(_user(is_verified=True))
    assert onboarded is not None

    # No profile at all yet (bootstrap creates one lazily) — still allowed to read.
    fresh = _user(is_verified=True, profile=None)
    assert await require_email_confirmed_user(fresh) is fresh


async def test_unconfirmed_email_is_refused_regardless_of_profile():
    """The converse: a finished profile never substitutes for confirming the address.

    This state is **not reachable today**, and the test is an ordering invariant rather than a
    fix for a live hole. Confirmation necessarily precedes onboarding (no session is issued until
    the email is confirmed, and onboarding cannot save without one); `_sync_and_return` only ever
    moves `is_verified` false->true; and the single place that sets it back, account deletion,
    clears `profile_completed` and `is_active` in the same breath, so `_ensure_active` rejects
    those accounts with a 401 before this guard is reached.

    It is pinned because one future change would make it reachable: an email-change flow. The
    send-email hook already routes `email_change` actions, so the backend is half-prepared for it.
    Supabase marks a user unconfirmed for the *new* address while their profile stays complete —
    exactly this combination. If that flow ships, this test is what keeps it from silently
    granting Campus Hub access on the strength of an unverified address.
    """
    with pytest.raises(HTTPException) as exc:
        await require_email_confirmed_user(
            _user(is_verified=False, profile=SimpleNamespace(profile_completed=True))
        )
    assert exc.value.status_code == 403
    assert exc.value.detail == 'Verified account required'
