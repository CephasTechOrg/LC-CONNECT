"""OpenAPI snapshot guard — the core zero-regression proof.

The complete public API contract (paths, params, request/response schemas) is
serialized to a committed baseline. An internal file move must leave this
byte-identical. If this test fails during the refactor, a move changed behavior.

Regenerate the baseline intentionally (only when the API is *meant* to change):

    UPDATE_SNAPSHOTS=1 pytest tests/test_openapi_snapshot.py
"""

from __future__ import annotations

import json
import os

from tests.conftest import BASELINE_DIR

SNAPSHOT_FILE = BASELINE_DIR / "openapi.json"


def _normalize(spec: dict) -> str:
    # Sorted keys => stable, diff-friendly serialization independent of dict order.
    return json.dumps(spec, sort_keys=True, indent=2) + "\n"


def test_openapi_schema_matches_baseline(openapi) -> None:
    current = _normalize(openapi)

    if os.environ.get("UPDATE_SNAPSHOTS") == "1":
        BASELINE_DIR.mkdir(parents=True, exist_ok=True)
        SNAPSHOT_FILE.write_text(current)

    assert SNAPSHOT_FILE.exists(), (
        "Missing baseline. Generate it once with: "
        "UPDATE_SNAPSHOTS=1 pytest tests/test_openapi_snapshot.py"
    )

    expected = SNAPSHOT_FILE.read_text()
    assert current == expected, (
        "OpenAPI schema drifted from the committed baseline. During the "
        "feature-first refactor the API contract must not change. If this change "
        "is intentional, regenerate with UPDATE_SNAPSHOTS=1."
    )
