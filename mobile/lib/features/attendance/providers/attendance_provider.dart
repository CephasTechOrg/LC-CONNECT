import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../shared/util/eligibility.dart';
import '../../../shared/util/keep_fresh.dart';
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
///
/// **Errors propagate on purpose.** This used to be wrapped in `catch (_) { return false; }`, which
/// turned any transient failure — a cold-start timeout, a 401 mid token-refresh, campus Wi-Fi —
/// into "the feature is off", hiding every attendance surface for the rest of the session with no
/// error and no retry. A flag that cannot be read is *unknown*, not *off*; see [Eligibility].
///
/// Kept alive rather than `autoDispose` so the answer (and any failure) survives a tab switch, and
/// [keepFresh] recovers it on resume/reconnect instead of leaving it stuck.
final honorsAttendanceEnabledProvider = FutureProvider<bool>((ref) async {
  keepFresh(ref, onStale: ref.invalidateSelf);
  ref.watch(authNotifierProvider);
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/attendance/honors/status');
  return response.data['enabled'] as bool? ?? false;
});

/// Active Honors session for the signed-in scholar. Non-scholars get a closed state without calling
/// the API; a *failure* to establish eligibility propagates instead of masquerading as "closed".
final activeAttendanceProvider = FutureProvider.autoDispose<ActiveAttendanceState>((ref) async {
  ref.watch(authNotifierProvider);
  // All `watch` calls up front, before any `await` — an autoDispose Ref used after an async gap
  // throws once the provider has no listeners.
  final isScholar = ref.watch(isVerifiedScholarFutureProvider.future);
  final enabledFuture = ref.watch(honorsAttendanceEnabledProvider.future);
  final client = ref.watch(apiClientProvider);

  // Awaited, not read: the sync scholar provider reports pending while memberships are still
  // loading, so reading it here used to return `closed()` for a genuine scholar and surface
  // "Attendance is closed." on the scanner. Either await throwing is correct — it becomes an
  // AsyncError the caller can report as "couldn't check", never a false "closed".
  if (!await isScholar) return ActiveAttendanceState.closed();
  if (!await enabledFuture) return ActiveAttendanceState.closed();
  final response = await client.dio.get('/attendance/honors/active');
  return ActiveAttendanceState.fromJson(response.data as Map<String, dynamic>);
});

/// Whether the student should see any Honors attendance surface.
///
/// Both gates must permit: an active `presidential_scholars` membership **and** the backend feature
/// flag. [eligibilityAll] keeps a confirmed [Eligibility.no] (genuinely not a scholar) distinct
/// from [Eligibility.unknown] (we could not ask), so a surface can hide quietly in the first case
/// and offer a retry in the second.
///
/// Replaces a `Provider<bool>` that returned `false` for *all* of: not a scholar, still loading,
/// and request failed. Use [honorsAttendanceVisibleFutureProvider] when you need to *decide*
/// rather than paint.
final honorsAttendanceVisibleProvider = Provider<Eligibility>((ref) {
  return eligibilityAll([
    ref.watch(scholarEligibilityProvider),
    eligibilityFrom(ref.watch(honorsAttendanceEnabledProvider), (enabled) => enabled),
  ]);
});

/// Awaitable form of [honorsAttendanceVisibleProvider], for the scanner, which must not mistake
/// "still loading" for "not permitted" and show an error screen on the first frame.
///
/// **Throws** when eligibility cannot be established. Callers must distinguish that from `false`:
/// `false` means "not permitted", a throw means "couldn't check — retry". Collapsing the two is
/// what made the scanner tell genuine scholars the session was "not available for your account"
/// after a cold-start timeout.
final honorsAttendanceVisibleFutureProvider = FutureProvider.autoDispose<bool>((ref) async {
  // Every `watch` happens before the first `await`. On an autoDispose provider the Ref can be
  // disposed during an async gap, and touching it afterwards throws.
  final isScholar = ref.watch(isVerifiedScholarFutureProvider.future);
  final enabled = ref.watch(honorsAttendanceEnabledProvider.future);
  if (!await isScholar) return false;
  return enabled;
});

/// The in-app notification type the backend sends when an instructor opens a session.
///
/// Matches `ATTENDANCE_OPEN_NOTIFICATION` in `app/features/attendance/notifications.py`.
const attendanceOpenNotificationType = 'honors_attendance_open';

/// Refreshes [activeAttendanceProvider] the moment a session opens, instead of waiting for a poll.
///
/// The backend already pushes a realtime `notification` frame when an instructor opens a session,
/// but the only consumer was the bell counter — it bumped the badge and refetched the notification
/// list, and nothing told the attendance state to re-read. So a student sitting on the dashboard
/// saw the check-in card appear up to 30 seconds late, purely because the 30s poll timer was the
/// only thing looking. Worse, that timer lives on the card widget, so it only runs while the card
/// is mounted — and the card is hidden until a session exists.
///
/// Watch this wherever an attendance surface is rendered. The poll stays as a backstop for a
/// dropped frame; this is the fast path.
final attendanceRealtimeSyncProvider = Provider<void>((ref) {
  final StreamSubscription<InboundEvent> sub;
  try {
    sub = ref.watch(realtimeClientProvider).events.listen((event) {
      if (event is! NotificationEvent) return;
      if (event.notification['type'] != attendanceOpenNotificationType) return;
      ref.invalidate(activeAttendanceProvider);
    });
  } catch (_) {
    return; // realtime unavailable (widget tests, unset env) — the poll still covers it
  }
  ref.onDispose(sub.cancel);
});
