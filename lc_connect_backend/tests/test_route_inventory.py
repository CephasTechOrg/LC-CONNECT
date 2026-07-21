"""Route-inventory guard.

The set of (METHOD, PATH) operations exposed by the API must not change during
an internal refactor. Moving a router between packages must leave the exact same
routes registered. Regenerate the baseline intentionally with:

    UPDATE_SNAPSHOTS=1 pytest tests/test_route_inventory.py
"""

from __future__ import annotations

import os

from tests.conftest import BASELINE_DIR

ROUTES_FILE = BASELINE_DIR / "routes.txt"
_HTTP_METHODS = {"get", "post", "put", "patch", "delete", "options", "head"}


def _current_operations(openapi: dict) -> list[str]:
    ops = []
    for path, item in openapi.get("paths", {}).items():
        for method in item:
            if method.lower() in _HTTP_METHODS:
                ops.append(f"{method.upper()} {path}")
    return sorted(ops)


def test_route_inventory_matches_baseline(openapi) -> None:
    current = _current_operations(openapi)

    if os.environ.get("UPDATE_SNAPSHOTS") == "1":
        BASELINE_DIR.mkdir(parents=True, exist_ok=True)
        ROUTES_FILE.write_text("\n".join(current) + "\n")

    assert ROUTES_FILE.exists(), (
        "Missing baseline. Generate it once with: "
        "UPDATE_SNAPSHOTS=1 pytest tests/test_route_inventory.py"
    )

    expected = [line for line in ROUTES_FILE.read_text().splitlines() if line.strip()]
    missing = sorted(set(expected) - set(current))
    added = sorted(set(current) - set(expected))
    assert not missing and not added, (
        "Route inventory changed (this refactor must not alter the API surface).\n"
        f"  Missing (in baseline, not live): {missing}\n"
        f"  Added   (live, not in baseline): {added}"
    )
