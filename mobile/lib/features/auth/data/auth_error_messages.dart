import 'package:dio/dio.dart';
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
  // Login is two hops: Supabase sign-in, then a call to our own `/auth/bootstrap`. A failure in
  // the second hop is a [DioException], not an [AuthException] — collapsing every one of those into
  // "check your connection" hid the real reason (a rejected email, a suspended account, a server
  // that is merely waking up). Surface them distinctly so the user — and we — can act.
  if (error is DioException) {
    return _dioMessage(error);
  }

  if (error is! AuthException) {
    return 'Something went wrong. Please check your connection and try again.';
  }

  final retry = _retryHint(error.message);

  return switch (error.code) {
    'over_email_send_rate_limit' || 'over_request_rate_limit' || 'over_sms_send_rate_limit' =>
      'Too many attempts. Please wait ${retry ?? 'a few minutes'} before trying again.',
    'invalid_credentials' => 'That email or password is incorrect.',
    'email_not_confirmed' => 'Confirm your email first. Check your inbox for the code.',
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

/// A failure talking to our backend after Supabase sign-in succeeded.
///
/// No `response` means the request never got an HTTP reply — host unreachable, or (most common on
/// a free-tier host that idles) the server is cold-starting and blew past the connect timeout. With
/// a `response`, the backend's own `detail` is already user-facing copy (e.g. "Only Livingstone
/// College email addresses are allowed"), so prefer it over anything invented here.
String _dioMessage(DioException error) {
  final response = error.response;
  if (response == null) {
    return "Can't reach LC Connect. The server may be waking up, so try again in a moment.";
  }

  final data = response.data;
  final detail = data is Map ? data['detail'] : null;
  if (detail is String && detail.trim().isNotEmpty) {
    return detail;
  }

  final code = response.statusCode ?? 0;
  if (code == 401) return 'Your session expired. Please sign in again.';
  if (code >= 500) return 'The server ran into a problem. Please try again shortly.';
  return 'Something went wrong. Please try again.';
}

String _fallback(AuthException error, String? retry) {
  // A 429 that arrived without a recognised code is still plainly a rate limit.
  if (error.statusCode == '429') {
    return 'Too many attempts. Please wait ${retry ?? 'a few minutes'} before trying again.';
  }
  return 'Something went wrong. Please try again.';
}
