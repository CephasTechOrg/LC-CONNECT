import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/providers/opportunity_badge_provider.dart';

void main() {
  group('opportunitiesLastSeenKey', () {
    test('scopes the cursor per user', () {
      expect(
        opportunitiesLastSeenKey('user-a'),
        'campus_hub.opportunities_last_seen.user-a',
      );
      expect(
        opportunitiesLastSeenKey('user-a'),
        isNot(opportunitiesLastSeenKey('user-b')),
      );
    });
  });

  group('countNewOpportunities', () {
    final t0 = DateTime.utc(2026, 9, 1, 12);
    final t1 = DateTime.utc(2026, 9, 2, 12);
    final t2 = DateTime.utc(2026, 9, 3, 12);

    test('null lastSeen means first visit — zero new (caller baselines separately)', () {
      expect(countNewOpportunities(lastSeen: null, publishAts: [t0, t1]), 0);
    });

    test('counts only posts strictly after lastSeen', () {
      expect(
        countNewOpportunities(lastSeen: t1, publishAts: [t0, t1, t2]),
        1,
      );
    });

    test('markSeen equivalent — nothing after cursor → 0', () {
      expect(countNewOpportunities(lastSeen: t2, publishAts: [t0, t1, t2]), 0);
    });

    test('empty feed → 0', () {
      expect(countNewOpportunities(lastSeen: t0, publishAts: const []), 0);
    });
  });

  group('opportunityAudienceApplies', () {
    test('all reaches everyone', () {
      expect(opportunityAudienceApplies('all', 'student'), isTrue);
      expect(opportunityAudienceApplies('all', 'staff'), isTrue);
    });

    test('students / staff are role-gated', () {
      expect(opportunityAudienceApplies('students', 'student'), isTrue);
      expect(opportunityAudienceApplies('students', 'staff'), isFalse);
      expect(opportunityAudienceApplies('staff', 'student'), isFalse);
      expect(opportunityAudienceApplies('staff', 'staff'), isTrue);
    });
  });
}
