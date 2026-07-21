"""Discovery domain logic: the MVP match-scoring heuristic.

Simple and explainable by design (see the architecture review). Returns a score and
up to three human-readable reasons for surfacing a candidate.
"""

from __future__ import annotations

from app.models import Profile


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
