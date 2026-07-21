"""Shared test fixtures.

These tests are structural regression guards for the feature-first refactor.
They do NOT touch the database — they only inspect the assembled FastAPI app
(routes + OpenAPI schema), so no live Postgres/Supabase is required.
"""

from __future__ import annotations

from pathlib import Path

import pytest

BASELINE_DIR = Path(__file__).parent / "baseline"


@pytest.fixture(scope="session")
def app():
    from app.main import app as fastapi_app

    return fastapi_app


@pytest.fixture(scope="session")
def openapi(app) -> dict:
    return app.openapi()
