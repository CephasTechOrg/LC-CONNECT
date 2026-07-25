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
