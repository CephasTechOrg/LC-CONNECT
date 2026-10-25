import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/data/person_name.dart';
import 'package:lc_connect/features/auth/providers/auth_provider.dart';
import 'package:lc_connect/features/onboarding/data/suggested_name.dart';

/// Mirrors backend/tests/test_person_names.py — the form must accept and refuse what the server
/// does, or a student sees a generic signup failure instead of the field to fix.
void main() {
  group('validatePersonName', () {
    for (final ok in ['Ama', 'Mary Jane', "O'Neil", 'Ngozi-Adaeze', 'José', 'St. John', 'N’Golo']) {
      test('accepts "$ok"', () => expect(validatePersonName(ok, field: 'first name'), isNull));
    }
    for (final bad in ['', '   ', 'R2D2', 'Ama!', '<b>', '---', 'x' * (kMaxNameLength + 1)]) {
      test('refuses "$bad"', () => expect(validatePersonName(bad, field: 'first name'), isNotNull));
    }
    test('names the missing field', () {
      expect(validatePersonName('', field: 'last name'), 'Enter your last name');
    });
    test('tidies spacing the way the server stores it', () {
      expect(normalizePersonName('  Mary   Jane '), 'Mary Jane');
    });
  });

  group('names from bootstrap', () {
    Map<String, dynamic> json({String? first, String? last}) => {
          'id': 'u1',
          'email': 'ama.mensah@students.livingstone.edu',
          'first_name': first,
          'last_name': last,
        };

    test('are read and survive copyWith', () {
      final user = AuthUser.fromBootstrap(json(first: 'Ama', last: 'Mensah'));
      final updated = user.copyWith(profileCompleted: true);
      expect((updated.firstName, updated.lastName), ('Ama', 'Mensah'));
    });

    test('onboarding pre-fills the signup name, not the address', () {
      expect(suggestedDisplayName(AuthUser.fromBootstrap(json(first: 'Ama', last: 'Mensah'))),
          'Ama Mensah');
    });

    test('an account from before names were asked still gets a guess from its address', () {
      expect(suggestedDisplayName(AuthUser.fromBootstrap(json())), 'Ama Mensah');
    });

    test('onboarding welcomes by first name, with a plain title when there is none', () {
      final named = AuthUser.fromBootstrap(json(first: 'Ama', last: 'Mensah'));
      expect(onboardingWelcome(named, fallback: 'Set up your profile'), 'Welcome, Ama');
      expect(onboardingWelcome(AuthUser.fromBootstrap(json()), fallback: 'Set up your profile'),
          'Set up your profile');
    });
  });
}
