import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../auth/providers/auth_provider.dart';
import '../../programs/providers/programs_provider.dart';

class AttendanceSessionInfo {
  final String id;
  final String title;
  final DateTime openedAt;
  final DateTime presentUntil;
  final DateTime? lateUntil;
  final String status;

  const AttendanceSessionInfo({
    required this.id,
    required this.title,
    required this.openedAt,
    required this.presentUntil,
    this.lateUntil,
    required this.status,
  });

  factory AttendanceSessionInfo.fromJson(Map<String, dynamic> json) => AttendanceSessionInfo(
        id: json['id'] as String,
        title: json['title'] as String,
        openedAt: DateTime.parse(json['opened_at'] as String),
        presentUntil: DateTime.parse(json['present_until'] as String),
        lateUntil: json['late_until'] == null ? null : DateTime.parse(json['late_until'] as String),
        status: json['status'] as String,
      );

  DateTime get closesAt => lateUntil ?? presentUntil;
}

class ActiveAttendanceState {
  final bool open;
  final AttendanceSessionInfo? session;
  final String? studentStatus;
  final DateTime? checkedInAt;

  const ActiveAttendanceState({
    required this.open,
    this.session,
    this.studentStatus,
    this.checkedInAt,
  });

  factory ActiveAttendanceState.closed() => const ActiveAttendanceState(open: false);

  factory ActiveAttendanceState.fromJson(Map<String, dynamic> json) {
    if (json['open'] != true) return ActiveAttendanceState.closed();
    final sessionJson = json['session'] as Map<String, dynamic>?;
    return ActiveAttendanceState(
      open: true,
      session: sessionJson == null ? null : AttendanceSessionInfo.fromJson(sessionJson),
      studentStatus: json['student_status'] as String?,
      checkedInAt: json['checked_in_at'] == null ? null : DateTime.parse(json['checked_in_at'] as String),
    );
  }

  bool get isCheckedIn => studentStatus == 'present' || studentStatus == 'late';
}

class AttendanceCheckInResult {
  final String status;
  final DateTime? checkedInAt;
  final String sessionId;
  final String message;
  final bool alreadyCheckedIn;

  const AttendanceCheckInResult({
    required this.status,
    required this.checkedInAt,
    required this.sessionId,
    required this.message,
    required this.alreadyCheckedIn,
  });

  factory AttendanceCheckInResult.fromJson(Map<String, dynamic> json) => AttendanceCheckInResult(
        status: json['status'] as String,
        checkedInAt: json['checked_in_at'] == null ? null : DateTime.parse(json['checked_in_at'] as String),
        sessionId: json['session_id'] as String,
        message: json['message'] as String,
        alreadyCheckedIn: json['already_checked_in'] as bool? ?? false,
      );

  bool get isPresent => status == 'present';
  bool get isLate => status == 'late';
}

/// Whether the backend has Honors attendance turned on.
final honorsAttendanceEnabledProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  try {
    final response = await client.dio.get('/attendance/honors/status');
    return response.data['enabled'] as bool? ?? false;
  } catch (_) {
    return false;
  }
});

/// Active Honors session for the signed-in scholar. Non-scholars get a closed state without calling the API.
final activeAttendanceProvider = FutureProvider.autoDispose<ActiveAttendanceState>((ref) async {
  ref.watch(authNotifierProvider);
  if (!ref.watch(isVerifiedScholarProvider)) return ActiveAttendanceState.closed();

  final enabled = await ref.watch(honorsAttendanceEnabledProvider.future);
  if (!enabled) return ActiveAttendanceState.closed();

  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/attendance/honors/active');
  return ActiveAttendanceState.fromJson(response.data as Map<String, dynamic>);
});

/// True when the student should see any Honors attendance surfaces.
final honorsAttendanceVisibleProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(isVerifiedScholarProvider)) return false;
  final enabled = ref.watch(honorsAttendanceEnabledProvider).value;
  return enabled == true;
});
