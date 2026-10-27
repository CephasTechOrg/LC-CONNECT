import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/campus_hub/data/greeting_name.dart';

/// Locks the greeting name resolution that fixes the "old name flashes, then corrects" report:
/// the current saved profile name wins over the signup name, and nothing is derived until the
/// profile has resolved (so the email-derived fallback never flashes first).
void main() {
  group('resolveGreetingName', () {
    test('returns null while the profile is still loading', () {
      expect(
        resolveGreetingName(
          firstName: 'Cephas',
          email: 'cephas@students.livingstone.edu',
          profileResolved: false,
        ),
        isNull,
      );
    });

    test('prefers the saved profile display name over the signup first name', () {
      // The rename case: signup says "Cephas", the student later set their display name to
      // "Kwame Osei". The greeting must show the current name, not the stale signup one.
      expect(
        resolveGreetingName(
          firstName: 'Cephas',
          displayName: 'Kwame Osei',
          email: 'cephas@students.livingstone.edu',
          profileResolved: true,
        ),
        'Kwame',
      );
    });

    test('falls back to the signup first name when the profile has no display name', () {
      expect(
        resolveGreetingName(
          firstName: 'Cephas',
          displayName: '  ',
          email: 'cephas@students.livingstone.edu',
          profileResolved: true,
        ),
        'Cephas',
      );
    });

    test('uses the capitalized email local part only when no name exists', () {
      expect(
        resolveGreetingName(
          email: 'ama.boateng@students.livingstone.edu',
          profileResolved: true,
        ),
        'Ama.boateng',
      );
    });

    test('falls back to "there" when nothing is available', () {
      expect(resolveGreetingName(profileResolved: true), 'there');
      expect(resolveGreetingName(email: '', profileResolved: true), 'there');
    });
  });
}
