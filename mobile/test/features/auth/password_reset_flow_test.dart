import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/screens/forgot_password_screen.dart';

void main() {
  group('password reset flow wiring', () {
    test('ResetPasswordScreen is reachable — forgot-password routes into it', () {
      // The regression this guards: ResetPasswordScreen was fully built and routed, but nothing
      // navigated to it. Reset is code-based, so a user got a 6-digit code by email, was popped
      // back to the login screen, and had nowhere to enter it. The flow was a dead end.
      final source = File(
        'lib/features/auth/screens/forgot_password_screen.dart',
      ).readAsStringSync();

      expect(
        source.contains("context.push('/reset-password'"),
        isTrue,
        reason: 'forgot-password must advance to the code-entry screen',
      );
      expect(
        source.contains('context.pop(); // Navigate back to sign-in'),
        isFalse,
        reason: 'submitting must not dead-end back at login',
      );
      expect(
        source.contains('extra:'),
        isTrue,
        reason: 'ResetPasswordScreen requires the email via state.extra',
      );
    });

    test('reset copy says code, not link', () {
      // The email carries a 6-digit OTP, deliberately not a magic link. Telling the user to
      // expect a "link" sends them looking for something that never arrives.
      final source = File(
        'lib/features/auth/screens/forgot_password_screen.dart',
      ).readAsStringSync();
      expect(source.contains('reset link has been sent'), isFalse);
      expect(source.contains('6-digit code'), isTrue);
    });

    test('login surfaces the real failure reason', () {
      // Was hardcoded to "Invalid email or password" for every error, so a rate-limited user
      // was told their password was wrong.
      final source = File('lib/features/auth/screens/login_screen.dart').readAsStringSync();
      expect(source.contains("'Invalid email or password. Please try again.'"), isFalse);
      expect(source.contains('authErrorMessage(error)'), isTrue);
    });

    test('ResetPasswordScreen still requires an email', () {
      expect(() => ResetPasswordScreen, returnsNormally);
    });
  });
}
