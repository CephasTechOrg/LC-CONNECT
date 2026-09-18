import 'package:flutter/material.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

class AppErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final IconData icon;

  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            // Live region on the message alone — see [AppInlineMessage]. Wrapping the whole
            // block announced the message twice and hid Retry from a screen reader, which is
            // the one control a failed state exists to offer.
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                'Retry',
                style: AppTypography.body.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.border),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(
                  actionLabel!,
                  style: AppTypography.body.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Card-style empty state used on Home feed sections.
class AppEmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const AppEmptyStateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xl),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl,
                vertical: AppSpacing.md,
              ),
            ),
            child: Text(
              actionLabel,
              style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact message with an optional retry, for use *inside* a panel or section.
///
/// [AppErrorState] is a full-screen block — a 48px icon with 40px of padding — which is why three
/// screens hand-rolled their own small version instead of using it: `_Message` in the notification
/// inbox, `_PanelMessage` in the groups panel, and `_ErrorRetry` in group detail. All three were
/// slightly different (13px vs default text, 60px vs 24px top padding), and none of them had the
/// two things that matter:
///
///  * **A live-region announcement.** A screen-reader user got silence where a sighted user got
///    "Couldn't load this" — the state existed only visually.
///  * **A 48px tap target on Retry.** A bare `TextButton` is shorter than that, so the one
///    actionable control in a failed state was the hardest thing on screen to hit.
///
/// The compact treatment is a real need, not laziness; this is that need met once.
class AppInlineMessage extends StatelessWidget {
  const AppInlineMessage({
    super.key,
    required this.message,
    this.onRetry,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
  });

  final String message;

  /// When null the message stands alone — an empty state rather than a failure.
  final VoidCallback? onRetry;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The live region is on the text alone, deliberately. Wrapping the whole column would
          // announce the message twice (once from the annotation, once from the `Text`) and would
          // swallow the Retry button's own semantics, making the only actionable control in a
          // failed state invisible to a screen reader.
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                'Retry',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [AppEmptyState] inside a scroller, so pull-to-refresh still works with nothing to show.
///
/// Three screens had an identical private wrapper for this — `ListView` with
/// `AlwaysScrollableScrollPhysics`, a proportional top spacer, then the shared empty state. The
/// scroll physics are the load-bearing part: a `RefreshIndicator` over a non-scrollable child has
/// nothing to pull, so an empty list could not be refreshed at all.
class AppScrollableEmptyState extends StatelessWidget {
  const AppScrollableEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.topFraction = 0.12,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// How far down the viewport the state sits, as a fraction of its height. The three call sites
  /// used 0.12, 0.14 and 0.18 — nothing depended on the difference.
  final double topFraction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Not optional: without it there is nothing for a RefreshIndicator to pull on.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * topFraction),
        AppEmptyState(
          icon: icon,
          title: title,
          subtitle: subtitle,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
      ],
    );
  }
}
