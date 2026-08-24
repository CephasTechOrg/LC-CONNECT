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
    "overrides",
    [{"status": "suspended"}, {"is_active": False}],
)
def test_inactive_or_suspended_is_unauthorized(overrides):
    with pytest.raises(HTTPException) as exc:
        _ensure_active(_user(**overrides))
    assert exc.value.status_code == 401


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
