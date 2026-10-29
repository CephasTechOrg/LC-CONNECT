import 'package:dio/dio.dart';

/// Turns a failed API call into a clean, user-facing message.
///
/// Prefers the backend's own `detail` (e.g. a 429 "you've sent too many… try again tomorrow",
/// or a 400/403/409 explanation), which is written to be shown to users. Falls back to the
/// caller's friendly default for network errors or unexpected shapes — we never surface a raw
/// exception or a stack trace.
String apiErrorMessage(Object error, {required String fallback}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
      final fieldError = validationMessage(detail);
      if (fieldError != null) return fieldError;
    }
    // Timeouts / no connection → a clearer network message than the generic fallback.
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'No connection — check your internet and try again.';
    }
  }
  return fallback;
}

/// The HTTP status a failed call came back with, or null when the request never got a response
/// (no connection, timeout, a server still spinning up). That distinction is what lets a caller
/// tell "the server rejected this" from "we could not reach the server yet" — the first is
/// final, the second is worth retrying.
int? apiStatusCode(Object error) => error is DioException ? error.response?.statusCode : null;

/// Field names the API can reject, as people would say them. Anything not listed is humanized
/// from its snake_case key.
const _fieldLabels = {
  'linkedin_url': 'LinkedIn URL',
  'handshake_url': 'Handshake URL',
  'url': 'Project link',
  'summary': 'Summary',
  'skills': 'Skills',
  'career_interests': 'Career interests',
};

/// The first problem in a FastAPI 422 `detail` list, named by field: "LinkedIn URL: URL must
/// start with http:// or https://". A validation error used to fall through to the caller's
/// generic fallback, so a single bad field on a long form read as "Something went wrong".
String? validationMessage(Object? detail) {
  if (detail is! List || detail.isEmpty) return null;
  final first = detail.first;
  if (first is! Map) return null;
  final raw = first['msg'];
  if (raw is! String || raw.trim().isEmpty) return null;
  final msg = raw.replaceFirst(RegExp(r'^Value error,\s*'), '').trim();
  final loc = first['loc'];
  final key = loc is List ? loc.whereType<String>().where((s) => s != 'body').lastOrNull : null;
  if (key == null) return msg;
  final label = _fieldLabels[key] ?? _humanize(key);
  return '$label: $msg';
}

String _humanize(String key) {
  final words = key.replaceAll('_', ' ').trim();
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}
