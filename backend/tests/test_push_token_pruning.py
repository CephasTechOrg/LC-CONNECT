"""Which FCM failures delete a device token — review Part 3 finding #11.

The finding said `SenderIdMismatch` and `ThirdPartyAuthError` were "logged but never pruned", only
`UnregisteredError` being deleted, and implied both should be. **Only one of them should.**

`ThirdPartyAuthError` means APNs refused *our* credential — typically the .p8 missing for the
environment a token belongs to, which the module's own docstring already explains. The token is
perfectly good; the server is misconfigured. Pruning on it would delete every iOS token in the
table during an outage, and they would only return as each user next opened the app. That turns a
fixable config error into permanent data loss, so it is excluded on purpose — and this file exists
so the exclusion reads as a decision rather than an omission someone should "fix".

DB-free: `_is_dead_token` classifies one send result and nothing else.
"""

from __future__ import annotations

from dataclasses import dataclass

from firebase_admin import messaging

from app.features.notifications.push import _is_dead_token


@dataclass
class _Result:
    """The shape of one entry in an FCM batch response."""

    success: bool
    exception: Exception | None = None


def test_unregistered_is_pruned():
    # The app was uninstalled, or the token was replaced. It will never work again.
    assert _is_dead_token(_Result(False, messaging.UnregisteredError('gone'))) is True


def test_sender_id_mismatch_is_pruned():
    # The token belongs to a different Firebase project, so this project can never deliver to it.
    # This is the half of finding #11 that was right.
    assert _is_dead_token(_Result(False, messaging.SenderIdMismatchError('wrong project'))) is True


def test_third_party_auth_error_is_not_pruned():
    """The half that was wrong, and the reason this is a named check rather than "prune failures".

    A missing or wrong APNs key fails *every* iOS token at once. Deleting them would be an
    irreversible response to a reversible problem.
    """
    assert _is_dead_token(_Result(False, messaging.ThirdPartyAuthError('bad .p8'))) is False


def test_an_unknown_failure_is_not_pruned():
    # Default to keeping the token: a transient or unrecognised error must not cost a user their
    # notifications.
    assert _is_dead_token(_Result(False, RuntimeError('who knows'))) is False


def test_a_successful_send_is_not_pruned():
    assert _is_dead_token(_Result(True)) is False
