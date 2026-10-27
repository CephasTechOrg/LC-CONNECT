"""Unit tests for discovery ranking (`rank_candidates`).

Pure and DB-free: `calculate_match` / `rank_candidates` only read plain attributes, so lightweight
stand-ins are enough. These pin the behaviours the pre-launch refinement introduced — full-pool
scoring (no arbitrary pre-cut), deterministic tie-breaking, and a within-tie diversity pass.
"""

from __future__ import annotations

import types

from app.features.discovery.service import calculate_match, rank_candidates


def _profile(
    user_id: str,
    *,
    major: str | None = None,
    interests: tuple[str, ...] = (),
    looking: tuple[str, ...] = (),
    class_year: int | None = None,
) -> types.SimpleNamespace:
    return types.SimpleNamespace(
        user_id=user_id,
        major=major,
        class_year=class_year,
        interests=[types.SimpleNamespace(name=name) for name in interests],
        looking_for_options=[types.SimpleNamespace(code=code) for code in looking],
        languages=[],
    )


def _ids(ranked: list) -> list[str]:
    return [profile.user_id for _, _, profile in ranked]


def test_scores_the_full_pool_not_an_arbitrary_prefix() -> None:
    # The strongest match sits last in input order; it must still surface within the limit.
    me = _profile('me', major='Math', interests=('chess', 'hiking'))
    weak = [_profile(f'w{i}') for i in range(10)]
    strong = _profile('strong', major='Math', interests=('chess', 'hiking'))
    ranked = rank_candidates(me, [*weak, strong], limit=3)
    assert _ids(ranked)[0] == 'strong'


def test_respects_the_limit() -> None:
    me = _profile('me')
    pool = [_profile(f'p{i}') for i in range(10)]
    assert len(rank_candidates(me, pool, limit=4)) == 4


def test_ties_break_deterministically_on_user_id() -> None:
    me = _profile('me', interests=('x',))
    # Both share exactly one interest → identical score; input order is reversed.
    b = _profile('b', interests=('x',))
    a = _profile('a', interests=('x',))
    assert _ids(rank_candidates(me, [b, a], limit=10)) == ['a', 'b']
    assert _ids(rank_candidates(me, [a, b], limit=10)) == ['a', 'b']


def test_equal_scores_round_robin_by_major_for_diversity() -> None:
    me = _profile('me', interests=('x',))  # no major → no major bonus for anyone
    c1 = _profile('1', major='Math', interests=('x',))
    c2 = _profile('2', major='Math', interests=('x',))
    c3 = _profile('3', major='Bio', interests=('x',))
    # All score 25. Sorted by user_id: 1, 2, 3. Round-robin by major spreads the two Math profiles.
    assert _ids(rank_candidates(me, [c3, c2, c1], limit=10)) == ['1', '3', '2']


def test_diversity_never_outranks_a_better_score() -> None:
    me = _profile('me', major='Math', interests=('x', 'y'))
    best = _profile('best', major='Math', interests=('x', 'y'))  # high score
    other = _profile('other', major='Bio', interests=('x',))  # lower score
    ranked = rank_candidates(me, [other, best], limit=10)
    assert _ids(ranked)[0] == 'best'


def test_calculate_match_still_caps_interest_contribution() -> None:
    me = _profile('me', interests=('a', 'b', 'c', 'd', 'e'))
    candidate = _profile('c', interests=('a', 'b', 'c', 'd', 'e'))
    score, reasons = calculate_match(me, candidate)
    assert score == 75  # 5 shared interests → capped at 75, not 125
    assert reasons
