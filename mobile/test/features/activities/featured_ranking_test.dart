import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/activities/data/featured_ranking.dart';
import 'package:lc_connect/features/activities/providers/activities_provider.dart';

/// `selectFeatured` is the hero-card ranking. These tests pin its behaviour with an injected `now`,
/// so the pick is deterministic and the signals (timing / scarcity / participation / fairness) each
/// earn their place rather than defaulting to "whatever the API returned first".

final _now = DateTime(2026, 10, 27, 9);

Activity _act(
  String id, {
  required int hoursFromNow,
  int? maxParticipants,
  int participantCount = 0,
  bool hasJoined = false,
  bool isCancelled = false,
}) =>
    Activity(
      id: id,
      creatorId: 'u-$id',
      title: 'Activity $id',
      category: 'social',
      location: 'Somewhere',
      startTime: _now.add(Duration(hours: hoursFromNow)),
      maxParticipants: maxParticipants,
      participantCount: participantCount,
      hasJoined: hasJoined,
      isCancelled: isCancelled,
    );

void main() {
  group('selectFeatured', () {
    test('returns null for an empty pool', () {
      expect(selectFeatured(const [], now: _now), isNull);
    });

    test('ignores past and cancelled activities', () {
      final past = _act('past', hoursFromNow: -2, participantCount: 50);
      final cancelled =
          _act('cancelled', hoursFromNow: 5, participantCount: 50, isCancelled: true);
      final live = _act('live', hoursFromNow: 10, participantCount: 1);

      final pick = selectFeatured([past, cancelled, live], now: _now);
      expect(pick, isNotNull);
      expect(pick!.activity.id, 'live');
    });

    test('returns null when every activity is past or cancelled', () {
      final pool = [
        _act('past', hoursFromNow: -1),
        _act('cancelled', hoursFromNow: 3, isCancelled: true),
      ];
      expect(selectFeatured(pool, now: _now), isNull);
    });

    test('prefers the sooner event when other signals are equal', () {
      final soon = _act('soon', hoursFromNow: 6, participantCount: 5, maxParticipants: 20);
      final later = _act('later', hoursFromNow: 120, participantCount: 5, maxParticipants: 20);

      final pick = selectFeatured([later, soon], now: _now);
      expect(pick!.activity.id, 'soon');
    });

    test('does not feature a full event over a joinable one', () {
      // Same timing; the full event is a dead end and must lose despite high participation.
      final full = _act('full', hoursFromNow: 30, participantCount: 30, maxParticipants: 30);
      final joinable =
          _act('joinable', hoursFromNow: 30, participantCount: 12, maxParticipants: 30);

      final pick = selectFeatured([full, joinable], now: _now);
      expect(pick!.activity.id, 'joinable');
    });

    test('deprioritises an event the viewer already joined', () {
      final joined =
          _act('joined', hoursFromNow: 20, participantCount: 8, maxParticipants: 20, hasJoined: true);
      final fresh =
          _act('fresh', hoursFromNow: 20, participantCount: 8, maxParticipants: 20);

      final pick = selectFeatured([joined, fresh], now: _now);
      expect(pick!.activity.id, 'fresh');
    });

    test('breaks exact ties deterministically on id', () {
      final b = _act('b', hoursFromNow: 24, participantCount: 5, maxParticipants: 20);
      final a = _act('a', hoursFromNow: 24, participantCount: 5, maxParticipants: 20);

      // Order of the input must not change the outcome; smaller id wins.
      expect(selectFeatured([b, a], now: _now)!.activity.id, 'a');
      expect(selectFeatured([a, b], now: _now)!.activity.id, 'a');
    });

    group('label reason', () {
      test('"Filling up" when nearly full', () {
        final pick = selectFeatured(
          [_act('x', hoursFromNow: 100, participantCount: 18, maxParticipants: 20)],
          now: _now,
        );
        expect(pick!.reason, FeaturedReason.fillingUp);
        expect(pick.label, 'Filling up');
      });

      test('"Starting soon" within 48h when not nearly full', () {
        final pick = selectFeatured(
          [_act('x', hoursFromNow: 12, participantCount: 2, maxParticipants: 20)],
          now: _now,
        );
        expect(pick!.reason, FeaturedReason.startingSoon);
        expect(pick.label, 'Starting soon');
      });

      test('"Popular" when well-attended but not soon or nearly full', () {
        final pick = selectFeatured(
          [_act('x', hoursFromNow: 120, participantCount: 15, maxParticipants: 100)],
          now: _now,
        );
        expect(pick!.reason, FeaturedReason.popular);
        expect(pick.label, 'Popular');
      });

      test('"Featured" as the neutral fallback', () {
        final pick = selectFeatured(
          [_act('x', hoursFromNow: 120, participantCount: 2, maxParticipants: 100)],
          now: _now,
        );
        expect(pick!.reason, FeaturedReason.featured);
        expect(pick.label, 'Featured');
      });
    });
  });
}
