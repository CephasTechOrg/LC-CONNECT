part of '../screens/activities_screen.dart';

/// The join button on the featured card. Shape unchanged; the colours now mean the same thing as
/// the round buttons below it — blue to join, soft blue once joined, grey when full. It used to
/// turn *green* once joined, while green on the round buttons meant "join".
class _JoinButton extends StatelessWidget {
  final bool joined;
  final bool loading;
  final bool full;
  final VoidCallback onTap;
  final String title;
  const _JoinButton({
    required this.joined,
    required this.loading,
    required this.full,
    required this.onTap,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = joined
        ? (AppColors.primarySoft, AppColors.primaryText)
        : full
            ? (AppColors.quiet, AppColors.textMuted)
            : (AppColors.primary, Colors.white);

    return Semantics(
      container: true,
      button: true,
      enabled: !full,
      label: _rsvpLabel(joined: joined, full: full, title: title),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: full || loading ? null : onTap,
        // 48dp target around the 36dp button.
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                    )
                  : Text(
                      joined
                          ? '✓ Joined'
                          : full
                              ? 'Full'
                              : 'Join',
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Compact join/leave button (circle icon) ───────────────────────

/// The round button on each list row. Same 30dp circle; the colours follow the featured button
/// (it used to be *green* to join), "full" shows a block icon instead of a "+" that looked
/// tappable, and the tap area is 48dp around the circle.
class _CompactJoinButton extends StatelessWidget {
  final bool joined;
  final bool loading;
  final bool full;
  final VoidCallback onTap;
  final String title;
  const _CompactJoinButton({
    required this.joined,
    required this.loading,
    required this.full,
    required this.onTap,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final (fill, icon, iconColor) = joined
        ? (AppColors.primarySoft, Icons.check_rounded, AppColors.primaryText)
        : full
            ? (AppColors.quiet, Icons.block_rounded, AppColors.textMuted)
            : (AppColors.primary, Icons.add_rounded, Colors.white);

    return Semantics(
      container: true,
      button: true,
      enabled: !full,
      label: _rsvpLabel(joined: joined, full: full, title: title),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: full || loading ? null : onTap,
        child: SizedBox(
          width: kMinInteractiveDimension,
          height: kMinInteractiveDimension,
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: loading
                  ? Padding(
                      padding: const EdgeInsets.all(7),
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: iconColor),
                    )
                  : Icon(icon, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

String _rsvpLabel({required bool joined, required bool full, required String title}) {
  if (joined) return "You're going to $title. Tap to leave";
  if (full) return '$title is full';
  return 'Join $title';
}

// ── Empty state ───────────────────────────────────────────────────
