---
description: Run the full LC Connect verification gate (backend tests+lint, mobile analyze, line limits)
---

Run the LC Connect verification gate and report a concise ✅/❌ summary for each step. Do NOT fix
anything unless I ask — just report.

1. **Backend tests** (API snapshot + route inventory + import smoke) — from `backend/`:
   `.venv/bin/pytest`
2. **Backend lint** — from `backend/`: `.venv/bin/ruff check .`
3. **Mobile analyze** — from `mobile/`: `flutter analyze`
4. **Line limits** (600 hard cap) — from repo root: `python3 scripts/check_line_limits.py`

For each, show pass/fail and the key line of output. If any step fails, surface the relevant error
and stop for my review. If the backend venv is missing, tell me to run
`python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt` in `backend/`.
