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
        expect(msg, contains(expected), reason: 'for code $code');
        expect(msg, isNot(contains('raw developer text')));
      }
    });

    test('non-auth errors fall back to a connection hint', () {
      expect(authErrorMessage(Exception('boom')), contains('connection'));
    });
  });
}
