import 'package:flutter_test/flutter_test.dart';
import 'package:lc_connect/features/auth/data/auth_error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('authErrorMessage', () {
    test('rate limit surfaces the actual wait from the message', () {
      final msg = authErrorMessage(AuthException(
        'For security purposes, you can only request this after 41 seconds.',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      ));
      expect(msg, contains('41 seconds'));
      expect(msg, isNot(contains('For security purposes')));
    });

    test('rounds a longer wait up to whole minutes', () {
      final msg = authErrorMessage(AuthException(
        'you can only request this after 90 seconds',
        statusCode: '429',
        code: 'over_request_rate_limit',
      ));
      expect(msg, contains('2 minutes'));
    });

    test('singular minute reads naturally', () {
      final msg = authErrorMessage(AuthException(
        'try again after 60 seconds',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      ));
      expect(msg, contains('a minute'));
    });

    test('rate limit without a parsable wait still gives guidance', () {
      final msg = authErrorMessage(AuthException(
        'email rate limit exceeded',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      ));
      expect(msg, contains('a few minutes'));
    });

    test('a 429 with an unknown code is still treated as a rate limit', () {
      final msg = authErrorMessage(
        AuthException('something new', statusCode: '429', code: 'brand_new_code'),
      );
      expect(msg, contains('Too many attempts'));
    });

    test('common auth failures get human copy, never the raw message', () {
      for (final (code, expected) in [
        ('invalid_credentials', 'incorrect'),
        ('email_not_confirmed', 'confirm your email'),
        ('otp_expired', 'expired'),
        ('user_already_exists', 'already exists'),
      ]) {
        final msg = authErrorMessage(
          AuthException('raw developer text', statusCode: '400', code: code),
        );
        // Case-insensitive: these assert that the copy says the right thing, not that a phrase
        // sits mid-sentence. Re-wording "Please confirm your email first" to start the sentence
        // with "Confirm" is a copy decision, not a regression.
        expect(msg.toLowerCase(), contains(expected), reason: 'for code $code');
        expect(msg, isNot(contains('raw developer text')));
      }
    });

    test('non-auth errors fall back to a connection hint', () {
      expect(authErrorMessage(Exception('boom')), contains('connection'));
    });
  });

  // Signup broke for every new user and the only evidence was a screenshot of "Something went
  // wrong. Please try again." Supabase's reply never reaches our server logs, and this mapper
  // replaced it with a generic sentence — so the failure was invisible from both ends.
  group('a failure the mapper cannot explain still leaves a trace', () {
    test('an unknown code is carried as a reference', () {
      final msg = authErrorMessage(
        const AuthException('Error sending confirmation email',
            statusCode: '400', code: 'some_new_code'),
      );
      expect(msg, contains('Something went wrong'));
      expect(msg, contains('(Ref: some_new_code)'));
    });

    test('with no code, the HTTP status is the reference', () {
      final msg = authErrorMessage(const AuthException('x', statusCode: '418'));
      expect(msg, contains('(Ref: http_418)'));
    });

    test('the raw Supabase message is never shown', () {
      // The code is a documented identifier; the message is developer text that may echo input.
      final msg = authErrorMessage(
        const AuthException('Error sending confirmation email',
            statusCode: '400', code: 'some_new_code'),
      );
      expect(msg, isNot(contains('Error sending confirmation email')));
    });
  });

  group('a server-side failure says whose side failed', () {
    test('a 5xx is not presented as something the user did', () {
      // "Please try again" alone sends people back round the form re-checking details that were
      // fine all along. A 5xx is Supabase, or a hook it called, failing — never bad input.
      final msg = authErrorMessage(
        const AuthException('Error sending confirmation email',
            statusCode: '500', code: 'unexpected_failure'),
      );
      expect(msg, contains('on our side'));
      expect(msg, contains('(Ref: unexpected_failure)'));
    });

    test('a failing email hook says the email could not be sent', () {
      for (final code in [
        'hook_timeout',
        'hook_timeout_after_retry',
        'hook_payload_over_size_limit',
        'hook_payload_invalid_content_type',
      ]) {
        final msg = authErrorMessage(AuthException('x', statusCode: '500', code: code));
        expect(msg, contains('verification email'), reason: 'for $code');
      }
    });

    test('a 429 is still a rate limit, not a server failure', () {
      final msg = authErrorMessage(const AuthException('x', statusCode: '429'));
      expect(msg, contains('Too many attempts'));
      expect(msg, isNot(contains('on our side')));
    });
  });
}
