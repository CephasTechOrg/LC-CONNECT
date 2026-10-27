"""Discovery domain logic: the MVP match-scoring heuristic and candidate ranking.

Simple and explainable by design (see the architecture review). Returns a score and
up to three human-readable reasons for surfacing a candidate.
"""

from __future__ import annotations

from collections import OrderedDict

from app.models import Profile

# A scored candidate: its match score, up to three reasons, and the profile itself.
ScoredCandidate = tuple[int, list[str], Profile]


def calculate_match(current: Profile, candidate: Profile) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []

    current_interests = {i.name.lower() for i in current.interests}
    candidate_interests = {i.name.lower() for i in candidate.interests}
    common_interests = sorted(current_interests & candidate_interests)
    if common_interests:
        score += min(len(common_interests) * 25, 75)
        reasons.append(f'You both like {common_interests[0].title()}')

    if current.major and candidate.major and current.major.strip().lower() == candidate.major.strip().lower():
        score += 35
        reasons.append(f'Both in {candidate.major}')

    current_looking = {item.code for item in current.looking_for_options}
    candidate_looking = {item.code for item in candidate.looking_for_options}
    common_goals = current_looking & candidate_looking
    if common_goals:
        score += min(len(common_goals) * 20, 60)
        if 'study_partner' in common_goals:
            reasons.append('Both looking for study partners')
        elif 'language_exchange' in common_goals:
            reasons.append('Both open to language exchange')
        elif 'friendship' in common_goals:
            reasons.append('Both looking for friendship')

    current_spoken = {row.language.name.lower() for row in current.languages if row.kind == 'speaks'}
    current_learning = {row.language.name.lower() for row in current.languages if row.kind == 'learning'}
    candidate_spoken = {row.language.name.lower() for row in candidate.languages if row.kind == 'speaks'}
    candidate_learning = {row.language.name.lower() for row in candidate.languages if row.kind == 'learning'}
    if (current_spoken & candidate_learning) or (candidate_spoken & current_learning):
        score += 30
        reasons.append('Good language exchange match')

    if current.class_year and candidate.class_year and current.class_year == candidate.class_year:
        score += 10
        reasons.append(f'Both class of {current.class_year}')

    if not reasons:
        reasons.append('New student to discover')
    return score, reasons[:3]


def rank_candidates(current: Profile, candidates: list[Profile], *, limit: int) -> list[ScoredCandidate]:
    """Score the full eligible pool, then order it deterministically with a light diversity pass.

    - **Full pool:** every eligible candidate is scored. Previously the query truncated to an
      arbitrary, unordered first 150 rows *before* scoring, so a strong match sitting outside that
      window was dropped before it could ever be compared. Scoring happens here, over everyone.
    - **Deterministic ties:** primary order is score descending; equal scores break on ``user_id``,
      so the same viewer sees a stable, reproducible order instead of whatever the DB happened to
      return.
    - **Diversity/fairness:** within a run of equal scores we round-robin by major, so a single
      program can't monopolise a tie block. This never reorders across scores — a better match
      always ranks above a worse one — it only spreads out equally-good candidates.
    """
    scored: list[ScoredCandidate] = []
    for candidate in candidates:
        score, reasons = calculate_match(current, candidate)
        scored.append((score, reasons, candidate))
    scored.sort(key=lambda item: (-item[0], str(item[2].user_id)))
    return _diversify_equal_score_runs(scored)[:limit]


def _diversify_equal_score_runs(scored: list[ScoredCandidate]) -> list[ScoredCandidate]:
    """Round-robin by major *within* each equal-score run; order across runs is untouched.

    Assumes ``scored`` is already sorted by score desc then ``user_id`` (so bucket and within-bucket
    order are deterministic). Candidates without a major share one bucket.
    """
    ordered: list[ScoredCandidate] = []
    i, n = 0, len(scored)
    while i < n:
        j = i
        while j < n and scored[j][0] == scored[i][0]:
            j += 1
        ordered.extend(_round_robin_by_major(scored[i:j]))
        i = j
    return ordered


def _round_robin_by_major(run: list[ScoredCandidate]) -> list[ScoredCandidate]:
    if len(run) < 3:
        return run  # nothing to spread out
    buckets: OrderedDict[str, list[ScoredCandidate]] = OrderedDict()
    for item in run:
        key = (item[2].major or '').strip().lower()
        buckets.setdefault(key, []).append(item)
    result: list[ScoredCandidate] = []
    while buckets:
        for key in list(buckets.keys()):
            result.append(buckets[key].pop(0))
            if not buckets[key]:
                del buckets[key]
    return result
