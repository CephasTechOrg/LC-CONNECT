import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/activities/providers/activities_provider.dart';
import 'package:lc_connect/features/activities/screens/activities_screen.dart';

final _now = DateTime(2026, 10, 29, 12);

Activity _a(String id, {String category = 'social', int hours = 24, bool joined = false, int? endHours}) => Activity(
      id: id,
      creatorId: 'c',
      title: id,
      category: category,
      location: 'Quad',
      startTime: _now.add(Duration(hours: hours)),
      endTime: endHours == null ? null : _now.add(Duration(hours: endHours)),
      participantCount: 3,
      hasJoined: joined,
    );

void main() {
  group('heroFor', () {
    test("the server's pick leads, using the list's copy so RSVP state stays live", () {
      final listed = _a('fair', joined: true);
      final (hero, label) = heroFor(
        [_a('soon', hours: 2), listed],
        server: ServerFeatured(_a('fair'), 'pinned'),
        filter: 'all',
        now: _now,
      );
      expect(identical(hero, listed), isTrue);
      expect(label, 'Campus pick');
    });

    test('a pick outside the selected category gives way to the local choice', () {
      final (hero, _) = heroFor(
        [_a('study', category: 'study', hours: 3)],
        server: ServerFeatured(_a('fair', category: 'career'), 'pinned'),
        filter: 'study',
        now: _now,
      );
      expect(hero.id, 'study');
    });

    test('an older server sends nothing, and the app still picks', () {
      final (hero, label) = heroFor([_a('later', hours: 200), _a('soon', hours: 5)], server: null, filter: 'all', now: _now);
      expect(hero.id, 'soon');
      expect(label, 'Starting soon');
    });
  });

  test('an activity counts as happening between its start and end, or two hours with no end', () {
    expect(_a('a', hours: -1, endHours: 1).isHappeningNow(_now), isTrue);
    expect(_a('b', hours: -1).isHappeningNow(_now), isTrue);
    expect(_a('c', hours: -3).isHappeningNow(_now), isFalse);
    expect(_a('d', hours: 1).isHappeningNow(_now), isFalse);
  });
}
