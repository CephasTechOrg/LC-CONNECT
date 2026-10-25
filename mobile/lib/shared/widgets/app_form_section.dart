import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import 'app_card.dart';

/// One card of a form: an optional numbered title, then its fields.
///
/// Lifted out of the Create activity form so every form in the app groups its fields the same
/// way — Compose post used to run eleven fields down one bare column.
class AppFormSection extends StatelessWidget {
  final String? title;

  /// Shown in a small brand-tinted circle before the title, so the required sections read as
  /// short steps (DESIGN_PRINCIPLES: a numbered step is a tinted circle plus text).
  final int? step;
  final List<Widget> children;
  const AppFormSection({super.key, this.title, this.step, required this.children});

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final step = this.step;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (step != null) ...[
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$step',
                        style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(
                    title,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A heading over a group of sections — "Optional" after the required steps, with one muted
/// line saying why the fields are worth filling in.
class AppFormGroupHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const AppFormGroupHeading({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xxl, AppSpacing.xs, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.title.copyWith(color: AppColors.textDark)),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

/// The bar pinned under a form that holds its primary action, so the action is always in reach
/// instead of at the end of a long scroll.
class AppFormActionBar extends StatelessWidget {
  final Widget child;
  const AppFormActionBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [BoxShadow(color: Color(0x0F1B3A5C), blurRadius: 16, offset: Offset(0, -4))],
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.md + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: child,
    );
  }
}
