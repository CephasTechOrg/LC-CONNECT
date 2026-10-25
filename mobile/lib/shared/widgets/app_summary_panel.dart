import 'package:flutter/material.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';

/// One key fact in an [AppSummaryPanel] — an icon, a short label, and the value.
class AppSummaryFact {
  final IconData icon;
  final String label;
  final String value;

  const AppSummaryFact({required this.icon, required this.label, required this.value});
}

/// The bottom panel of a detail page: the two or three facts that decide whether to act, laid out
/// as columns, with the page's one primary action under them.
///
/// The facts and the action used to be in two places — a details card mid-page and a separate
/// bar pinned below it — so deciding meant scrolling between them. Here they sit together, within
/// thumb reach, the way a product page puts size and price beside "Add to cart".
///
/// Navy, not brand blue: the same deep surface as Home's "Latest updates" panel, so the app has
/// one "featured" treatment rather than a new colour per page.
class AppSummaryPanel extends StatelessWidget {
  final List<AppSummaryFact> facts;

  /// 0–1, drawn under the facts — e.g. how full an activity is. Null hides it.
  final double? progress;

  /// A short line beside the action, e.g. "You're going". Null lets the action span the width.
  final Widget? status;

  final Widget action;

  const AppSummaryPanel({
    super.key,
    required this.facts,
    required this.action,
    this.progress,
    this.status,
  });

  static const navy = Color(0xFF1B3A5C);
  static const navyLight = Color(0xFF264A6E);

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final status = this.status;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [navyLight, navy],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x291B3A5C), blurRadius: 20, offset: Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xl,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final fact in facts) Expanded(child: _FactColumn(fact: fact))],
              ),
              if (progress != null) ...[
                const SizedBox(height: AppSpacing.lg),
                ClipRRect(
                  borderRadius: AppRadii.all(AppRadii.full),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (status != null) ...[
                    Expanded(child: status),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: action),
                  ] else
                    Expanded(child: action),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FactColumn extends StatelessWidget {
  final AppSummaryFact fact;
  const _FactColumn({required this.fact});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${fact.label}: ${fact.value}',
      excludeSemantics: true,
      child: Column(
        children: [
          Icon(fact.icon, size: 22, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            fact.label,
            style: AppTypography.caption.copyWith(color: Colors.white.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 2),
          Text(
            fact.value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// The panel's action: a white pill on the navy (filled), or a white outline for the quieter
/// choice such as "Leave". Disabled reads as a faint fill — never a tappable-looking button.
class AppSummaryAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outlined;

  const AppSummaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full));
    final text = AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700);
    final child = loading
        ? SizedBox(
            width: 18,
            height: 18,
            // White either way: while loading the button is disabled, so its fill is faint.
            child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Text(label, style: text);
    const size = Size.fromHeight(52);

    if (outlined) {
      return OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: size,
          shape: shape,
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: size,
        shape: shape,
        backgroundColor: AppColors.surface,
        foregroundColor: AppSummaryPanel.navy,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.18),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.85),
      ),
      child: child,
    );
  }
}
