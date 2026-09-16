import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lc_connect/shared/util/app_date_format.dart';

/// These tests are written to pass in **any** machine timezone.
///
/// The bug this module exists to prevent is formatting a UTC-flagged DateTime without converting
/// it, which prints UTC wall-clock time labelled as local. Asserting a hardcoded "6:00 PM" would
/// only hold on an EDT machine, so the invariant is expressed instead as: *the same instant must
/// format identically whether it arrives UTC-flagged or local.* That is false for a
/// `DateFormat(...).format(x)` call with a missing `.toLocal()`, and true here.
void main() {
  // 2026-09-16 22:00 UTC === 6:00 PM EDT. This exact instant is the reported regression.
  final instantUtc = DateTime.utc(2026, 9, 16, 22, 0);
  final instantLocal = instantUtc.toLocal();

  group('timezone invariant', () {
    test('a UTC-flagged and a local DateTime for the same instant format identically', () {
      expect(instantUtc.isUtc, isTrue, reason: 'guards the premise of this test');
      expect(instantLocal.isUtc, isFalse);

      expect(AppDateFormat.time(instantUtc), AppDateFormat.time(instantLocal));
      expect(AppDateFormat.date(instantUtc), AppDateFormat.date(instantLocal));
      expect(AppDateFormat.fullDate(instantUtc), AppDateFormat.fullDate(instantLocal));
      expect(AppDateFormat.dayMonth(instantUtc), AppDateFormat.dayMonth(instantLocal));
      expect(AppDateFormat.dateTime(instantUtc), AppDateFormat.dateTime(instantLocal));
      expect(
        AppDateFormat.timeRange(instantUtc, null),
        AppDateFormat.timeRange(instantLocal, null),
      );
    });

    test('formats the local wall clock, not the UTC one', () {
      // Equivalent to what a correct call site would produce by hand.
      expect(AppDateFormat.time(instantUtc), DateFormat('h:mm a').format(instantUtc.toLocal()));
    });

    test('the reported case: 22:00 UTC reads as 6:00 PM where the zone is UTC-4', () {
      // Beta report #9: an activity created for ~6:00 PM displayed as 10:00 PM. Asserted only
      // where the machine zone actually puts this instant at UTC-4 (e.g. TZ=America/New_York,
      // which is EDT in September) so the test stays portable; elsewhere the invariant tests
      // above already cover the behaviour.
      if (instantLocal.timeZoneOffset != const Duration(hours: -4)) return;
      expect(AppDateFormat.time(instantUtc), '6:00 PM');
      expect(AppDateFormat.time(instantUtc), isNot('10:00 PM'));
      expect(AppDateFormat.fullDate(instantUtc), 'Wednesday, September 16, 2026');
    });

    test('regression: a UTC-flagged instant is not formatted as raw UTC', () {
      // The old bug was `DateFormat('h:mm a').format(activity.startTime)` with startTime UTC —
      // it printed the UTC hour. Skip where the machine genuinely runs at UTC, since there the
      // buggy and correct outputs coincide and the assertion proves nothing.
      final offset = instantLocal.timeZoneOffset;
      if (offset == Duration.zero) return;
      final rawUtcRendering = DateFormat('h:mm a').format(instantUtc);
      expect(AppDateFormat.time(instantUtc), isNot(rawUtcRendering));
    });
  });

  group('timeRange', () {
    test('renders both ends separated by an en dash', () {
      final end = instantUtc.add(const Duration(hours: 2));
      expect(
        AppDateFormat.timeRange(instantUtc, end),
        '${AppDateFormat.time(instantUtc)} – ${AppDateFormat.time(end)}',
      );
    });

    test('renders only the start when there is no end', () {
      expect(AppDateFormat.timeRange(instantUtc, null), AppDateFormat.time(instantUtc));
    });
  });

  group('relative', () {
    final now = DateTime.utc(2026, 9, 16, 22, 0);

    test('buckets elapsed time', () {
      expect(AppDateFormat.relative(now, now: now), 'Just now');
      expect(AppDateFormat.relative(now.subtract(const Duration(seconds: 30)), now: now), 'Just now');
      expect(AppDateFormat.relative(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(AppDateFormat.relative(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(AppDateFormat.relative(now.subtract(const Duration(days: 2)), now: now), '2d ago');
      expect(AppDateFormat.relative(now.subtract(const Duration(days: 21)), now: now), '3w ago');
    });

    test('falls back to a date beyond four weeks', () {
      final old = now.subtract(const Duration(days: 60));
      expect(AppDateFormat.relative(old, now: now), AppDateFormat.dayMonth(old));
    });

    test('a future timestamp reads as Just now rather than a negative age', () {
      expect(AppDateFormat.relative(now.add(const Duration(hours: 5)), now: now), 'Just now');
    });
  });

  group('listStamp', () {
    test('shows a clock time for the same local day', () {
      final now = DateTime.now();
      final earlierToday = DateTime(now.year, now.month, now.day, 1, 5);
      expect(AppDateFormat.listStamp(earlierToday, now: now), AppDateFormat.time(earlierToday));
    });

    test('shows a weekday within the last week', () {
      final now = DateTime.now();
      final threeDaysAgo = now.subtract(const Duration(days: 3));
      expect(AppDateFormat.listStamp(threeDaysAgo, now: now), DateFormat('EEE').format(threeDaysAgo));
    });

    test('shows a date beyond a week', () {
      final now = DateTime.now();
      final longAgo = now.subtract(const Duration(days: 30));
      expect(AppDateFormat.listStamp(longAgo, now: now), AppDateFormat.dayMonth(longAgo));
    });
  });

  group('day bucketing', () {
    test('dayBucket returns local midnight and is stable across the isUtc flag', () {
      expect(AppDateFormat.dayBucket(instantUtc), AppDateFormat.dayBucket(instantLocal));
      final bucket = AppDateFormat.dayBucket(instantUtc);
      expect(bucket.hour, 0);
      expect(bucket.minute, 0);
      expect(bucket.isUtc, isFalse);
    });

    test('daySeparator labels Today and Yesterday', () {
      final now = DateTime.now();
      expect(AppDateFormat.daySeparator(now, now: now), 'Today');
      expect(
        AppDateFormat.daySeparator(now.subtract(const Duration(days: 1)), now: now),
        'Yesterday',
      );
    });

    test('daySeparator falls back to a date beyond a week', () {
      final now = DateTime.now();
      final longAgo = now.subtract(const Duration(days: 30));
      expect(
        AppDateFormat.daySeparator(longAgo, now: now),
        AppDateFormat.dayMonth(longAgo),
      );
    });
  });
}
