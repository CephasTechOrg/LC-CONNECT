"""Import smoke test: every module under app/ must import cleanly.

Catches dangling imports left behind by a file move during the feature-first
migration — the cheapest possible regression signal.
"""

from __future__ import annotations

import importlib
import pkgutil

import app


def _all_module_names() -> list[str]:
    names = [app.__name__]
    for info in pkgutil.walk_packages(app.__path__, prefix=f"{app.__name__}."):
        names.append(info.name)
    return sorted(names)


def test_every_app_module_imports() -> None:
    failures: list[str] = []
    for name in _all_module_names():
        try:
            importlib.import_module(name)
        except Exception as exc:  # noqa: BLE001 - we want the full failure list
            failures.append(f"{name}: {type(exc).__name__}: {exc}")
    assert not failures, "Modules failed to import:\n" + "\n".join(failures)
