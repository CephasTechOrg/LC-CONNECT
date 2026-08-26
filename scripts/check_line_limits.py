#!/usr/bin/env python3
"""Enforce the LC Connect file-length rules across backend (.py) and mobile (.dart).

Rules (see CONVENTIONS.md):
  - target/normal : <= 400 lines  (soft — printed as a warning)
  - hard cap      : <= 600 lines  (fails CI with a non-zero exit code)

The line count is a proxy for single-responsibility, not a law of physics: a file
just over the cap is a prompt to split or justify, not a bug. Genuine, reviewed
exceptions can be added to ALLOWLIST below with a reason.

Usage:
    python scripts/check_line_limits.py           # check the whole repo
    python scripts/check_line_limits.py --warn-only
    python scripts/check_line_limits.py path/to/dir ...
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SOFT_LIMIT = 400
HARD_LIMIT = 600

REPO_ROOT = Path(__file__).resolve().parent.parent

# Directories we never lint (generated code, deps, build output).
EXCLUDE_DIRS = {
    ".git", ".venv", "venv", "build", ".dart_tool", "node_modules",
    "__pycache__", ".pytest_cache", ".ruff_cache", "alembic",
    "ios", "android", "macos", "windows", "linux", "web",
    # Scratch pip --target installs (never commit; see .gitignore).
    "_vendor_redis",
}

# Reviewed, intentional exceptions: {relative_path: reason}. Keep this list short.
ALLOWLIST: dict[str, str] = {}

INCLUDE_SUFFIXES = {".py", ".dart"}


def _iter_source_files(roots: list[Path]):
    for root in roots:
        if root.is_file():
            if root.suffix in INCLUDE_SUFFIXES:
                yield root
            continue
        for path in root.rglob("*"):
            if path.suffix not in INCLUDE_SUFFIXES:
                continue
            if any(part in EXCLUDE_DIRS for part in path.parts):
                continue
            if path.name.endswith((".g.dart", ".freezed.dart")):
                continue
            yield path


def _count_lines(path: Path) -> int:
    with path.open("rb") as fh:
        return sum(1 for _ in fh)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="Files/dirs to check (default: whole repo).")
    parser.add_argument("--warn-only", action="store_true", help="Never exit non-zero.")
    args = parser.parse_args()

    roots = [Path(p).resolve() for p in args.paths] or [REPO_ROOT]

    warnings: list[tuple[str, int]] = []
    violations: list[tuple[str, int]] = []

    for path in sorted(_iter_source_files(roots)):
        rel = str(path.relative_to(REPO_ROOT)) if path.is_relative_to(REPO_ROOT) else str(path)
        if rel in ALLOWLIST:
            continue
        lines = _count_lines(path)
        if lines > HARD_LIMIT:
            violations.append((rel, lines))
        elif lines > SOFT_LIMIT:
            warnings.append((rel, lines))

    if warnings:
        print(f"\n⚠️  {len(warnings)} file(s) over the {SOFT_LIMIT}-line soft target (consider splitting):")
        for rel, lines in warnings:
            print(f"   {lines:>5}  {rel}")

    if violations:
        print(f"\n❌  {len(violations)} file(s) over the {HARD_LIMIT}-line HARD cap:")
        for rel, lines in violations:
            print(f"   {lines:>5}  {rel}")
        print("\nSplit these into smaller units, or add a reviewed exception to ALLOWLIST.")
        if not args.warn_only:
            return 1

    if not warnings and not violations:
        print(f"✅  All source files within the {HARD_LIMIT}-line cap (target {SOFT_LIMIT}).")

    return 0


if __name__ == "__main__":
    sys.exit(main())
