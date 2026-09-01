import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import 'attendance_provider.dart';

class QrAttendancePayload {
  final int version;
  final String sessionId;
  final String challengeId;
  final String expiresAt;
  final String token;

  const QrAttendancePayload({
    required this.version,
    required this.sessionId,
    required this.challengeId,
    required this.expiresAt,
    required this.token,
  });

  static QrAttendancePayload? tryParse(String raw) {
    try {
      final json = jsonDecode(raw.trim()) as Map<String, dynamic>;
      final version = json['v'];
      final sessionId = json['session_id'];
      final challengeId = json['challenge_id'];
      final expiresAt = json['expires_at'];
      final token = json['token'];
      if (version is! num ||
          sessionId is! String ||
          challengeId is! String ||
          expiresAt is! String ||
          token is! String) {
        return null;
      }
      return QrAttendancePayload(
        version: version.toInt(),
        sessionId: sessionId,
        challengeId: challengeId,
        expiresAt: expiresAt,
        token: token,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toRequestBody() => {
        'challenge_id': challengeId,
        'expires_at': expiresAt,
        'token': token,
      };
}

Future<AttendanceCheckInResult> submitAttendanceCheckIn(
  WidgetRef ref,
  QrAttendancePayload payload,
) async {
  final client = ref.read(apiClientProvider);
  final response = await client.dio.post(
    '/attendance/sessions/${payload.sessionId}/check-in',
    data: payload.toRequestBody(),
  );
  return AttendanceCheckInResult.fromJson(response.data as Map<String, dynamic>);
}
