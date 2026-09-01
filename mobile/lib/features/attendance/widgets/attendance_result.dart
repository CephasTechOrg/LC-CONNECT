import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/attendance_provider.dart';

class AttendanceResultView extends StatelessWidget {
  final AttendanceSessionInfo? session;
  final AttendanceCheckInResult? result;
  final ActiveAttendanceState? active;
  final String? errorMessage;
  final VoidCallback? onScanAgain;
  final VoidCallback? onDone;

  const AttendanceResultView({
    super.key,
    this.session,
    this.result,
    this.active,
    this.errorMessage,
    this.onScanAgain,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return _ErrorBody(
        message: errorMessage!,
        onScanAgain: onScanAgain,
        onDone: onDone,
      );
    }

    final status = result?.status ?? active?.studentStatus;
    final checkedInAt = result?.checkedInAt ?? active?.checkedInAt;
    final title = session?.title ?? active?.session?.title ?? 'Honors Class';
    final isLate = status == 'late';
    final headline = isLate ? 'Check-in recorded' : "You're present";

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: AppColors.green, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            headline,
            style: GoogleFonts.dmSans(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: GoogleFonts.dmSans(fontSize: 16, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
          if (isLate) ...[
            const SizedBox(height: 8),
            Text(
              'Status: Late',
              style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMid),
            ),
          ],
          if (checkedInAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Checked in at ${DateFormat.jm().format(checkedInAt.toLocal())}',
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMuted),
            ),
          ],
          if (onDone != null) ...[
            const SizedBox(height: 28),
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback? onScanAgain;
  final VoidCallback? onDone;

  const _ErrorBody({required this.message, this.onScanAgain, this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          if (onScanAgain != null) ...[
            const SizedBox(height: 28),
            FilledButton(onPressed: onScanAgain, child: const Text('Scan again')),
          ] else if (onDone != null) ...[
            const SizedBox(height: 28),
            FilledButton(onPressed: onDone, child: const Text('Done')),
          ],
        ],
      ),
    );
  }
}
