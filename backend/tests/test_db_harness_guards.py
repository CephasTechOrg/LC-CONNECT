"""Guards for the Postgres integration harness (DB-free).

Ensures CI cannot silently skip the DB suite: REQUIRE_TEST_DB must be recognized.
"""

from __future__ import annotations

import os

from tests.db.conftest import _require_test_db


def test_require_test_db_false_by_default(monkeypatch):
    monkeypatch.delenv('REQUIRE_TEST_DB', raising=False)
    assert _require_test_db() is False


def test_require_test_db_true_for_ci_values(monkeypatch):
    for value in ('1', 'true', 'YES', 'True'):
        monkeypatch.setenv('REQUIRE_TEST_DB', value)
        assert _require_test_db() is True, value


def test_require_test_db_false_for_off_values(monkeypatch):
    for value in ('0', 'false', '', 'no'):
        monkeypatch.setenv('REQUIRE_TEST_DB', value)
        assert _require_test_db() is False, repr(value)
