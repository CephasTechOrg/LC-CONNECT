import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a Supabase auth failure into something a student can act on.
///
/// The screens used to show `AuthException.message` verbatim, which is written for developers:
/// "For security purposes, you can only request this after 41 seconds" or "email rate limit
/// exceeded" tell a user neither what went wrong in their terms nor when to try again.
///
/// Mapping is on [AuthException.code] — a documented, stable identifier — rather than on the
/// message text, which Supabase is free to reword at any time.
String authErrorMessage(Object error) {
  if (error is! AuthException) {
    return 'Something went wrong. Please check your connection and try again.';
  }

  final retry = _retryHint(error.message);

  return switch (error.code) {
    'over_email_send_rate_limit' || 'over_request_rate_limit' || 'over_sms_send_rate_limit' =>
      'Too many attempts. Please wait ${retry ?? 'a few minutes'} before trying again.',
    'invalid_credentials' => 'That email or password is incorrect.',
    'email_not_confirmed' => 'Please confirm your email first — check your inbox for the code.',
    'user_already_exists' || 'email_exists' =>
      'An account already exists for that email. Try signing in instead.',
    'otp_expired' => 'That code has expired. Request a new one.',
    'weak_password' => 'Please choose a stronger password.',
    'validation_failed' => 'Please check the details you entered and try again.',
    'user_banned' => 'This account has been suspended. Contact an administrator.',
    _ => _fallback(error, retry),
  };
}

/// Supabase encodes the wait in the message ("...after 41 seconds"), not in a field, so the one
/// genuinely useful number in a rate-limit error has to be read back out of the text. Failing to
/// find it is fine — the caller falls back to a vaguer but still honest phrase.
String? _retryHint(String message) {
  final match = RegExp(r'after (\d+) seconds?').firstMatch(message);
  if (match == null) return null;
  final seconds = int.tryParse(match.group(1)!);
  if (seconds == null) return null;
  if (seconds < 60) return '$seconds seconds';
  final minutes = (seconds / 60).ceil();
  return minutes == 1 ? 'a minute' : '$minutes minutes';
}

String _fallback(AuthException error, String? retry) {
  // A 429 that arrived without a recognised code is still plainly a rate limit.
  if (error.statusCode == '429') {
    return 'Too many attempts. Please wait ${retry ?? 'a few minutes'} before trying again.';
  }
  return 'Something went wrong. Please try again.';
}
