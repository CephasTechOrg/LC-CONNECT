import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/data/auth_error_messages.dart';
import 'package:lc_connect/features/auth/data/duplicate_signup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user({required List<UserIdentity>? identities}) => User(
      id: 'e7c1b1f0-0000-4000-8000-000000000001',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026, 9, 10).toIso8601String(),
      email: 'jane.doe@students.livingstone.edu',
      identities: identities,
    );

UserIdentity _identity() => UserIdentity(
      id: 'i1',
      identityId: 'id1',
      userId: 'e7c1b1f0-0000-4000-8000-000000000001',
      identityData: const {},
      provider: 'email',
      createdAt: DateTime.utc(2026, 9, 10).toIso8601String(),
      lastSignInAt: DateTime.utc(2026, 9, 10).toIso8601String(),
      updatedAt: DateTime.utc(2026, 9, 10).toIso8601String(),
    );

void main() {
  group('isDuplicateSignup', () {
    test('an existing campus email is detected by the empty identities list', () {
      // Supabase never errors here — it returns a decoy user with no identities so that signup
      // cannot be used to enumerate accounts. This empty list is the only available signal.
      final response = AuthResponse(user: _user(identities: const []));
      expect(isDuplicateSignup(response), isTrue);
    });

    test('a genuine new signup awaiting confirmation is NOT a duplicate', () {
      // The case this must not swallow: also has no session, but carries one real identity.
      // Getting this wrong would block every legitimate signup.
      final response = AuthResponse(user: _user(identities: [_identity()]));
      expect(isDuplicateSignup(response), isFalse);
    });

    test('a null identities list is not treated as a duplicate', () {
      // Older payloads and non-signup responses omit the field entirely. Absent is not empty,
      // and guessing "duplicate" here would reject real signups.
      final response = AuthResponse(user: _user(identities: null));
      expect(isDuplicateSignup(response), isFalse);
    });

    test('a response with no user at all is not a duplicate', () {
      expect(isDuplicateSignup(AuthResponse()), isFalse);
    });
  });

  test('the duplicate error reaches the user as actionable copy', () {
    // The thrown code must land on a branch of the mapper, not the generic fallback — otherwise
    // the user is told "Something went wrong" for a problem with an obvious next step.
    const error = AuthException(
      'An account already exists for that email.',
      code: 'user_already_exists',
    );
    final msg = authErrorMessage(error);
    expect(msg, contains('already exists'));
    expect(msg.toLowerCase(), contains('signing in'));
    expect(msg, isNot(contains('Something went wrong')));
  });
}
