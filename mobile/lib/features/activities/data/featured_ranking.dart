import 'dart:math' as math;

import '../providers/activities_provider.dart';

/// Why an activity earned the hero slot — drives an honest badge instead of a blanket "Featured".
enum FeaturedReason { startingSoon, fillingUp, popular, featured }

/// The chosen hero activity and the reason it was chosen.
class FeaturedPick {
  const FeaturedPick(this.activity, this.reason);

  final Activity activity;
  final FeaturedReason reason;

  /// The badge text. It states *why* this activity is highlighted, so the label is accurate rather
  /// than a generic "Featured" on every pick.
  String get label => switch (reason) {
        FeaturedReason.startingSoon => 'Starting soon',
        FeaturedReason.fillingUp => 'Filling up',
        FeaturedReason.popular => 'Popular',
        FeaturedReason.featured => 'Featured',
      };
}

// The three ranking signals, weighted. Bounded and summing to 1, so the base score stays in [0, 1]
// before the discovery penalty — no single signal can run away with the slot.
const double _wTiming = 0.45;
const double _wScarcity = 0.20;
const double _wParticipation = 0.35;

// An activity the viewer already joined is gently pushed down so the hero slot favours discovery,
// never off the list — just behind an equally-ranked activity they have not seen.
const double _joinedPenalty = 0.15;

// A full activity is a dead end for the hero slot: nobody new can act on it. Pushed down hard (on
// top of its low scarcity score) so a packed event does not sit at the top advertising a closed
// door. It can still be featured if literally everything else ranks lower.
const double _fullPenalty = 0.20;

// Thresholds for the badge reason.
const double _fillingUpRatio = 0.7;
const Duration _startingSoonWindow = Duration(hours: 48);
const int _popularThreshold = 10;

/// Deterministically choose which upcoming activity to feature.
///
/// Signals:
/// - **timing** — sooner upcoming events rank higher, via a smooth exponential decay (no cliff), so
///   the hero trends toward what is actually coming up without ever picking something in the past;
/// - **scarcity** — an event close to full is socially proven and urgent, so it ranks up; a *full*
///   one is pushed down, since featuring something nobody new can join is a dead end;
/// - **participation** — popularity relative to the current pool, so a well-attended event surfaces.
///
/// Fairness: an activity the viewer already joined is gently deprioritised (discovery over repeats),
/// and exact ties break on id so the choice is stable and never flickers between equal candidates.
///
/// Pure and injectable on [now], so it is fully testable. Returns null for an empty/ineligible pool.
FeaturedPick? selectFeatured(List<Activity> activities, {required DateTime now}) {
  final eligible = activities
      .where((a) => !a.isCancelled && a.startTime.isAfter(now))
      .toList();
  if (eligible.isEmpty) return null;

  final poolMax =
      eligible.fold<int>(0, (m, a) => math.max(m, a.participantCount));

  double scoreOf(Activity a) {
    final hoursUntil = a.startTime.difference(now).inMinutes / 60.0;
    // Half-ish-life around two to three days: today's and this week's events dominate.
    final timing = math.exp(-hoursUntil / 72.0);

    final double scarcity;
    final max = a.maxParticipants;
    if (max == null || max <= 0) {
      scarcity = 0.3; // unlimited capacity — mild, neither urgent nor dead.
    } else {
      final ratio = a.participantCount / max;
      scarcity = ratio >= 1.0 ? 0.1 : ratio.clamp(0.0, 1.0);
    }

    final participation = poolMax == 0 ? 0.0 : a.participantCount / poolMax;

    var score =
        _wTiming * timing + _wScarcity * scarcity + _wParticipation * participation;
    if (a.hasJoined) score -= _joinedPenalty;
    if (max != null && max > 0 && a.participantCount >= max) score -= _fullPenalty;
    return score;
  }

  var best = eligible.first;
  var bestScore = scoreOf(best);
  for (final a in eligible.skip(1)) {
    final s = scoreOf(a);
    // Higher score wins; an exact tie falls to the smaller id so the pick is reproducible.
    if (s > bestScore || (s == bestScore && a.id.compareTo(best.id) < 0)) {
      best = a;
      bestScore = s;
    }
  }
  return FeaturedPick(best, _reasonFor(best, now: now));
}

FeaturedReason _reasonFor(Activity a, {required DateTime now}) {
  final max = a.maxParticipants;
  final nearlyFull = max != null &&
      max > 0 &&
      a.participantCount / max >= _fillingUpRatio &&
      a.participantCount < max;
  if (nearlyFull) return FeaturedReason.fillingUp;
  if (a.startTime.difference(now) <= _startingSoonWindow) {
    return FeaturedReason.startingSoon;
  }
  if (a.participantCount >= _popularThreshold) return FeaturedReason.popular;
  return FeaturedReason.featured;
}
