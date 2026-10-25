import 'package:flutter/material.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/util/app_date_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../providers/attendance_provider.dart';

/// Why a scan ended without a check-in — each gets its own title, colour and way forward.
///
/// Every outcome used to be the same red alert with the server's sentence as a bold headline, so
/// "attendance is closed" (nobody's fault) looked like a failure, and a connection problem
/// offered "Scan again" when the fix was to retry loading.
enum AttendanceIssue {
  /// Access could not be checked — a timeout or dropped request. Retrying is the fix.
  connection,

  /// Confirmed not available for this account.
  notAvailable,

  /// The session is closed or the window passed.
  closed,

  /// The scanned code was not an attendance code, or had expired.
  badCode,

  /// The check-in request itself failed.
  failed,
}

// Colour only where it means something: green done, amber late or "try that again", red only
// for a real failure, grey for a plain fact like "closed". All AA as text on their tints.
const _successText = Color(0xFF15803D);
const _successTint = Color(0xFFDCFCE7);
const _amberText = Color(0xFFB45309);
const _amberTint = Color(0xFFFEF3C7);
const _dangerText = Color(0xFFB91C1C);
const _dangerTint = Color(0xFFFEE2E2);
const _quietTint = Color(0xFFEEF2F6);

class AttendanceResultView extends StatelessWidget {
  final AttendanceSessionInfo? session;
  final AttendanceCheckInResult? result;
  final ActiveAttendanceState? active;
  final String? errorMessage;
  final AttendanceIssue issue;

  /// The way forward after an issue: scan again, or retry loading for [AttendanceIssue.connection].
  final VoidCallback? onScanAgain;
  final VoidCallback? onDone;

  const AttendanceResultView({
    super.key,
    this.session,
    this.result,
    this.active,
    this.errorMessage,
    this.issue = AttendanceIssue.failed,
    this.onScanAgain,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final message = errorMessage;
    if (message != null) {
      return _IssueBody(issue: issue, message: message, onRetry: onScanAgain, onDone: onDone);
    }
    final status = result?.status ?? active?.studentStatus;
    return _SuccessBody(
      title: session?.title ?? active?.session?.title ?? 'Honors class',
      isLate: status == 'late',
      // No fresh result means the screen opened on a check-in that already exists.
      already: result?.alreadyCheckedIn ?? true,
      checkedInAt: result?.checkedInAt ?? active?.checkedInAt,
      onDone: onDone,
    );
  }
}

class _SuccessBody extends StatelessWidget {
  final String title;
  final bool isLate;
  final bool already;
  final DateTime? checkedInAt;
  final VoidCallback? onDone;

  const _SuccessBody({
    required this.title,
    required this.isLate,
    required this.already,
    required this.checkedInAt,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final checkedInAt = this.checkedInAt;
    final headline = already
        ? "You're already checked in"
        : isLate
            ? 'Checked in late'
            : "You're checked in";
    final line = already
        ? 'Nothing else to do — your check-in is saved.'
        : isLate
            ? 'You scanned after the on-time window, so this class counts as late.'
            : "You're marked present for this class.";
    return AttendanceMessageLayout(
      badge: AttendanceBadge(
        icon: isLate ? Icons.schedule_rounded : Icons.check_rounded,
        color: isLate ? _amberText : _successText,
        tint: isLate ? _amberTint : _successTint,
      ),
      title: headline,
      message: line,
      // A receipt: the three facts a student may be asked about later, in one card.
      details: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        child: Column(
          children: [
            _ReceiptRow(label: 'Class', child: _value(title)),
            if (checkedInAt != null) ...[
              const Divider(height: 1, color: AppColors.border),
              _ReceiptRow(label: 'Checked in', child: _value(AppDateFormat.time(checkedInAt))),
            ],
            const Divider(height: 1, color: AppColors.border),
            _ReceiptRow(
              label: 'Status',
              child: _StatusChip(
                label: isLate ? 'Late' : 'Present',
                color: isLate ? _amberText : _successText,
                tint: isLate ? _amberTint : _successTint,
              ),
            ),
          ],
        ),
      ),
      actionLabel: 'Done',
      onAction: onDone,
    );
  }

  static Widget _value(String text) => Text(
        text,
        textAlign: TextAlign.end,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textDark),
      );
}

class _IssueBody extends StatelessWidget {
  final AttendanceIssue issue;
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDone;

  const _IssueBody({required this.issue, required this.message, this.onRetry, this.onDone});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, Color tint, String title) = switch (issue) {
      AttendanceIssue.connection => (Icons.wifi_off_rounded, AppColors.textMuted, _quietTint,
          "Couldn't check your access"),
      AttendanceIssue.notAvailable => (Icons.lock_outline_rounded, AppColors.textMuted, _quietTint,
          'Not available for your account'),
      AttendanceIssue.closed => (Icons.event_busy_outlined, AppColors.textMuted, _quietTint,
          'Attendance is closed'),
      AttendanceIssue.badCode => (Icons.qr_code_2_rounded, _amberText, _amberTint,
          'Code not recognised'),
      AttendanceIssue.failed => (Icons.error_outline_rounded, _dangerText, _dangerTint,
          "Check-in didn't go through"),
    };
    final retry = onRetry;
    return AttendanceMessageLayout(
      badge: AttendanceBadge(icon: icon, color: color, tint: tint),
      title: title,
      // The server's sentence often just restates the title ("Attendance is closed."); then the
      // title says it once.
      message: _same(message, title) ? null : message,
      actionLabel: retry == null
          ? 'Done'
          : issue == AttendanceIssue.connection
              ? 'Try again'
              : 'Scan again',
      onAction: retry ?? onDone,
    );
  }

  static bool _same(String a, String b) {
    String key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return key(a) == key(b);
  }
}

/// Badge, title, one muted line and optional details, centred; the one action pinned below.
/// Every attendance outcome — and the camera-permission prompt — uses it, so they read as one flow.
class AttendanceMessageLayout extends StatelessWidget {
  final Widget badge;
  final String title;
  final String? message;
  final Widget? details;
  final String actionLabel;
  final VoidCallback? onAction;

  const AttendanceMessageLayout({
    super.key,
    required this.badge,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.details,
  });

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final details = this.details;
    final onAction = this.onAction;
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl, vertical: AppSpacing.xl),
                child: Column(
                  children: [
                    badge,
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.display.copyWith(color: AppColors.textDark),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: AppTypography.body.copyWith(color: AppColors.textMuted, height: 1.5),
                        ),
                      ),
                    ],
                    if (details != null) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      details,
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (onAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.lg,
              ),
              child: FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full)),
                ),
                child: Text(
                  actionLabel,
                  style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AttendanceBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color tint;
  const AttendanceBadge({super.key, required this.icon, required this.color, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 44),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _ReceiptRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Text(label, style: AppTypography.body.copyWith(color: AppColors.textMuted)),
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: Align(alignment: Alignment.centerRight, child: child)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color tint;
  const _StatusChip({required this.label, required this.color, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: tint, borderRadius: AppRadii.all(AppRadii.full)),
      child: Text(
        label,
        style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
