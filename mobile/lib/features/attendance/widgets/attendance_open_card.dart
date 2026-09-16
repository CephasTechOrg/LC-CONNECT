import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/attendance_provider.dart';

/// Campus Hub card — visible to active Honors students while a session is open.
///
/// Beta report #7: eligible students sometimes never saw it. Three causes, addressed here and in
/// the providers behind it:
///
/// 1. Any failure to establish eligibility read as "not eligible" and hid the card for the rest
///    of the session. The gate now separates those (see `Eligibility`), and a failure stays
///    recoverable through pull-to-refresh / resume / reconnect.
/// 2. A session opening reached an already-open dashboard only via a 30-second poll, because the
///    realtime notification had no attendance consumer — now [attendanceRealtimeSyncProvider].
/// 3. The countdown read a provider once per second. On an `autoDispose` provider each read can
///    start and dispose it again, so the deadline is captured locally instead.
class AttendanceOpenCard extends ConsumerStatefulWidget {
  const AttendanceOpenCard({super.key});

  /// Backstop for a dropped realtime frame. The fast path is the WS notification.
  static const pollInterval = Duration(seconds: 30);

  @override
  ConsumerState<AttendanceOpenCard> createState() => _AttendanceOpenCardState();
}

class _AttendanceOpenCardState extends ConsumerState<AttendanceOpenCard> {
  Timer? _refreshTimer;
  Timer? _countdownTimer;

  /// Captured from the session in `build`, so the per-second tick never touches a provider.
  DateTime? _closesAt;
  String _remaining = '';

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(
      AttendanceOpenCard.pollInterval,
      (_) => ref.invalidate(activeAttendanceProvider),
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _tick() {
    final closesAt = _closesAt;
    if (closesAt == null) return;
    final next = _remainingLabel(closesAt);
    if (next != _remaining && mounted) setState(() => _remaining = next);
  }

  /// `difference` works off epoch microseconds, so a UTC-flagged deadline is correct as-is.
  static String _remainingLabel(DateTime closesAt) {
    final left = closesAt.difference(DateTime.now());
    if (left.isNegative) return 'Closing now';
    final minutes = left.inMinutes;
    final seconds = left.inSeconds % 60;
    return 'Closes in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(attendanceRealtimeSyncProvider);

    // Hidden while not confirmed eligible. `unknown` is now distinguishable from `no`, but the
    // dashboard is not the place to surface it: a retry tile wedged between two other cards
    // would be noise for a surface that is absent most of the time. Pull-to-refresh, app resume
    // and socket reconnect all recover it.
    if (!ref.watch(honorsAttendanceVisibleProvider).isPermitted) {
      _closesAt = null;
      return const SizedBox.shrink();
    }

    final active = ref.watch(activeAttendanceProvider).value;
    final session = active?.session;
    if (active == null || !active.open || session == null) {
      _closesAt = null;
      return const SizedBox.shrink();
    }

    // Keep the local deadline in step with whatever the provider last returned.
    if (_closesAt != session.closesAt) {
      _closesAt = session.closesAt;
      _remaining = _remainingLabel(session.closesAt);
    }

    // Already checked in: the card stays, because the session is still open and the countdown is
    // still meaningful, but it must stop telling the student to scan. It used to read
    // "Scan to Check In" right through a successful check-in until the session closed.
    final checkedIn = active.isCheckedIn;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Semantics(
        container: true,
        label: checkedIn
            ? '${_statusLabel(active.studentStatus)}. ${session.title}. $_remaining'
            : 'Attendance is open. ${session.title}. $_remaining. Scan to check in',
        button: !checkedIn,
        excludeSemantics: true,
        child: Material(
          color: checkedIn ? AppColors.green : AppColors.primary,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            // Nothing left to do once checked in, and an action that cannot change anything is a
            // dead affordance — so the card stops being tappable.
            onTap: checkedIn ? null : () => context.push('/attendance/scan'),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (checkedIn) ...[
                        const Icon(Icons.check_circle_rounded, size: 15, color: Colors.white),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          checkedIn ? _statusLabel(active.studentStatus) : 'Attendance is open',
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    session.title,
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _remaining,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  if (!checkedIn) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Scan to Check In',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `late` is a recorded outcome — saying "You're checked in" for it would misrepresent the
  /// roster.
  static String _statusLabel(String? studentStatus) =>
      studentStatus == 'late' ? "You're checked in — marked late" : "You're checked in";
}
