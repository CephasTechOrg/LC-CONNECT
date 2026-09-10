import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('password reset flow wiring', () {
    final forgot =
        File('lib/features/auth/screens/forgot_password_screen.dart').readAsStringSync();
    final reset =
        File('lib/features/auth/screens/reset_password_screen.dart').readAsStringSync();

    test('forgot-password routes into the code-entry screen', () {
      // The regression this guards: ResetPasswordScreen was fully built and routed, but nothing
      // navigated to it. Reset is code-based, so a user got a code by email, was popped back to
      // the login screen, and had nowhere to enter it. The flow was a dead end.
      expect(
        forgot.contains("context.push('/reset-password'"),
        isTrue,
        reason: 'forgot-password must advance to the code-entry screen',
      );
      expect(
        forgot.contains('context.pop(); // Navigate back to sign-in'),
        isFalse,
        reason: 'submitting must not dead-end back at login',
      );
    });

    test('reset copy says code, not link', () {
      // The email carries an OTP, deliberately not a magic link — `action_link` and the code
      // encode the same single-use token, so clicking one burns the other. Telling the user to
      // expect a "link" sends them looking for something that never arrives.
      expect(forgot.contains('reset link has been sent'), isFalse);
      expect(forgot.contains('reset code'), isTrue);
    });

    test('the OTP length is defined once, not retyped per screen', () {
      // Supabase issues the code and its length is a project setting the app cannot control, so
      // it lives in a single constant. Three screens each hardcoding a literal is how the copy
      // and the validator drifted apart in the first place — the app said "8-digit" while this
      // very test still asserted "6-digit".
      final config = File('lib/features/auth/data/otp_config.dart').readAsStringSync();
      expect(config.contains('const int kOtpLength = 8'), isTrue);

      final verify =
          File('lib/features/auth/screens/verify_email_screen.dart').readAsStringSync();
      for (final entry in {'reset': reset, 'verify-email': verify}.entries) {
        expect(
          RegExp(r"\d-digit").hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} must interpolate kOtpLength, never a literal digit',
        );
        expect(entry.value.contains('kOtpLength'), isTrue);
      }
    });

    test('the code field is digits-only in fact, not just by keyboard hint', () {
      // keyboardType is a hint that hardware and third-party keyboards ignore, and a pasted code
      // can carry whitespace — which then failed validation as "numbers only".
      expect(reset.contains('FilteringTextInputFormatter.digitsOnly'), isTrue);
    });

    test('an expired code can be replaced from the reset screen', () {
      // "That code has expired. Request a new one" used to be a dead end: this screen had no
      // resend, so the only way out was guessing that the back arrow led somewhere useful.
      expect(reset.contains('sendPasswordReset'), isTrue);
      expect(reset.contains('_resendCooldown'), isTrue);
    });

    test('forgot-password throttles repeat sends locally', () {
      // Mobile calls Supabase directly, so the backend's IP + per-address caps on
      // /auth/forgot-password never apply. Without a local cooldown a double-tap burns the
      // user's own quota and returns a rate-limit error that reads as failure.
      expect(forgot.contains('_startCooldown'), isTrue);
    });

    test('login surfaces the real failure reason', () {
      // Was hardcoded to "Invalid email or password" for every error, so a rate-limited user
      // was told their password was wrong.
      final source = File('lib/features/auth/screens/login_screen.dart').readAsStringSync();
      expect(source.contains("'Invalid email or password. Please try again.'"), isFalse);
      expect(source.contains('authErrorMessage(error)'), isTrue);
    });

    test('no screen smuggles a hardcoded test-email bypass', () {
      // Five Gmail addresses used to skip the campus-domain check on the identity field — the
      // one field that decides student vs staff — and the production API rejected them anyway.
      for (final path in [
        'lib/features/auth/screens/register_screen.dart',
        'lib/features/auth/screens/forgot_password_screen.dart',
        'lib/features/auth/screens/login_screen.dart',
      ]) {
        expect(
          File(path).readAsStringSync().contains('_allowedTestEmails'),
          isFalse,
          reason: '$path must not bypass the campus-domain check',
        );
      }
    });
  });
}
