import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
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
    // "Scan to check in" right through a successful check-in until the session closed.
    final checkedIn = active.isCheckedIn;

    return Padding(
      // Top gap only — matches the other Home blocks, so hiding this card leaves no seam.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        0,
      ),
      child: Semantics(
        container: true,
        label: checkedIn
            ? '${_statusLabel(active.studentStatus)}. ${session.title}. $_remaining'
            : 'Attendance is open. ${session.title}. $_remaining. Scan to check in',
        button: !checkedIn,
        excludeSemantics: true,
        child: checkedIn
            ? _CheckedInCard(
                status: _statusLabel(active.studentStatus),
                title: session.title,
                remaining: _remaining,
              )
            : _OpenCard(
                title: session.title,
                remaining: _remaining,
                onTap: () => context.push('/attendance/scan'),
              ),
      ),
    );
  }

  /// `late` is a recorded outcome — saying "You're checked in" for it would misrepresent the
  /// roster.
  static String _statusLabel(String? studentStatus) =>
      studentStatus == 'late' ? "You're checked in — marked late" : "You're checked in";
}

/// Session open, not yet checked in: the one saturated card on Home, because it is the one thing
/// with a deadline that cannot be undone.
class _OpenCard extends StatelessWidget {
  final String title;
  final String remaining;
  final VoidCallback onTap;

  const _OpenCard({required this.title, required this.remaining, required this.onTap});

  static final _radius = AppRadii.all(AppRadii.sheet);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: _radius,
        boxShadow: AppShadows.tinted(AppColors.primary),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: _radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Attendance is open',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  title,
                  style: AppTypography.title.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  remaining,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppRadii.all(AppRadii.full),
                  ),
                  child: Text(
                    'Scan to check in',
                    textAlign: TextAlign.center,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
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

/// Checked in: done, nothing left to do — so it steps down to a calm white card instead of a
/// second saturated block. It used to turn solid green with white text: 2.5:1 contrast, and a
/// second accent colour on a page that otherwise has one. Not tappable — an action that cannot
/// change anything is a dead affordance.
class _CheckedInCard extends StatelessWidget {
  final String status;
  final String title;
  final String remaining;

  const _CheckedInCard({required this.status, required this.title, required this.remaining});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const AppIconTile(icon: Icons.check_circle_rounded),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: AppTypography.label.copyWith(color: AppColors.primaryText),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(color: AppColors.textDark),
                ),
                Text(
                  remaining,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
