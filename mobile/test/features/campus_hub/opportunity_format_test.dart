import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/data/opportunity_format.dart';

void main() {
  final now = DateTime(2026, 10, 29, 15); // a Thursday afternoon

  group('deadlineLabel', () {
    test('counts calendar days, so the afternoon does not lose a day', () {
      // Closes at 11:59 PM on Saturday: two days left all of Thursday. Rounding elapsed hours down
      // said "1 day left" by mid-afternoon.
      expect(deadlineLabel(DateTime(2026, 10, 31, 23, 59), 'job', now: now), (text: '2 days left', urgent: true));
    });

    test('today and tomorrow are said in words', () {
      expect(deadlineLabel(DateTime(2026, 10, 29, 23, 59), 'job', now: now).text, 'Closes today');
      expect(deadlineLabel(DateTime(2026, 10, 30, 12), 'job', now: now).text, 'Closes tomorrow');
    });

    test('later dates name the day, with the year only when it differs', () {
      expect(deadlineLabel(DateTime(2026, 11, 20), 'job', now: now), (text: 'Closes Nov 20', urgent: false));
      expect(deadlineLabel(DateTime(2027, 1, 8), 'job', now: now).text, 'Closes Jan 8, 2027');
    });

    test('no date reads by kind of role', () {
      expect(deadlineLabel(null, 'internship', now: now).text, 'Open until filled');
      expect(deadlineLabel(null, 'volunteer', now: now).text, 'Ongoing');
    });
  });

  test('a single card names a single type', () {
    expect(opportunityTypeLabel('internship'), 'Internship');
    expect(opportunityTypeLabel('volunteer'), 'Volunteer role');
    expect(opportunityTypeLabel(null), 'Opportunity');
  });

  test('posted dates add the year only when it is not this year', () {
    expect(postedLabel(DateTime(2026, 10, 3), now: now), 'Posted Oct 3');
    expect(postedLabel(DateTime(2025, 12, 1), now: now), 'Posted Dec 1, 2025');
  });
}
