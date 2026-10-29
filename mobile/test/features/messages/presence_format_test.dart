import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/messages/data/presence_format.dart';

void main() {
  final now = DateTime(2026, 10, 29, 18); // a Thursday

  test('online wins over any last-seen time', () {
    expect(presenceLabel(online: true, lastSeenAt: now, now: now), 'Online');
  });

  test('nothing to say when hidden or never seen', () {
    expect(presenceLabel(online: false, now: now), isNull);
  });

  test('today, yesterday, this week, then a date', () {
    expect(presenceLabel(online: false, lastSeenAt: DateTime(2026, 10, 29, 15, 40), now: now),
        'Last seen today at 3:40 PM');
    expect(presenceLabel(online: false, lastSeenAt: DateTime(2026, 10, 28, 9, 5), now: now),
        'Last seen yesterday at 9:05 AM');
    expect(presenceLabel(online: false, lastSeenAt: DateTime(2026, 10, 26, 20), now: now),
        'Last seen Monday at 8:00 PM');
    expect(presenceLabel(online: false, lastSeenAt: DateTime(2026, 10, 1, 20), now: now),
        'Last seen Oct 1');
  });
}
