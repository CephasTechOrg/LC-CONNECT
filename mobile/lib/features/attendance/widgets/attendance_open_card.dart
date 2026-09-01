import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/attendance_provider.dart';

String _remainingLabel(DateTime closesAt) {
  final diff = closesAt.difference(DateTime.now());
  if (diff.isNegative) return 'Closing soon';
  final minutes = diff.inMinutes;
  final seconds = diff.inSeconds % 60;
  return 'Closes in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Campus Hub card — only visible to active Honors students while a session is open.
class AttendanceOpenCard extends ConsumerStatefulWidget {
  const AttendanceOpenCard({super.key});

  @override
  ConsumerState<AttendanceOpenCard> createState() => _AttendanceOpenCardState();
}

class _AttendanceOpenCardState extends ConsumerState<AttendanceOpenCard> {
  Timer? _refreshTimer;
  Timer? _countdownTimer;
  String _remaining = '';

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.invalidate(activeAttendanceProvider);
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickCountdown());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _tickCountdown() {
    final session = ref.read(activeAttendanceProvider).value?.session;
    if (session == null) return;
    final next = _remainingLabel(session.closesAt);
    if (next != _remaining && mounted) setState(() => _remaining = next);
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(honorsAttendanceVisibleProvider)) return const SizedBox.shrink();

    final activeAsync = ref.watch(activeAttendanceProvider);
    final active = activeAsync.value;
    if (active == null || !active.open || active.session == null) {
      return const SizedBox.shrink();
    }

    final session = active.session!;
    if (_remaining.isEmpty) _remaining = _remainingLabel(session.closesAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Material(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => context.push('/attendance/scan'),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance is open',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
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
            ),
          ),
        ),
      ),
    );
  }
}
