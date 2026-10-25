import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import 'onboarding_shared_widgets.dart';

/// The top of both onboarding flows: the logo and flow name with the sign-out escape, the step
/// dots, then this step's title and one muted line.
///
/// Student and staff onboarding each hand-built this block, with a blue "LC" text square standing
/// in for the logo the rest of the app uses.
class OnboardingHeader extends StatelessWidget {
  final String flowTitle;
  final int step;
  final int totalSteps;
  final String stepTitle;
  final String stepSubtitle;

  const OnboardingHeader({
    super.key,
    required this.flowTitle,
    required this.step,
    required this.totalSteps,
    required this.stepTitle,
    required this.stepSubtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/lclogo.webp', width: 32, height: 32, fit: BoxFit.contain),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  flowTitle,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              // The only way out of onboarding — see [OnboardingSignOutButton].
              const OnboardingSignOutButton(),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.lg),
                OnboardingStepIndicator(currentStep: step, totalSteps: totalSteps),
                const SizedBox(height: AppSpacing.xl),
                Text(stepTitle, style: AppTypography.display.copyWith(color: AppColors.textDark)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  stepSubtitle,
                  style: AppTypography.body.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(color: AppColors.border, height: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbered steps as tinted circles joined by a line: done is a solid check, the current step is
/// solid, steps ahead are the soft tint with their number (DESIGN_PRINCIPLES).
class OnboardingStepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const OnboardingStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps * 2 - 1, (i) {
        if (i.isOdd) {
          final isComplete = (i ~/ 2) < currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              color: isComplete ? AppColors.primary : AppColors.border,
            ),
          );
        }
        final idx = i ~/ 2;
        final isComplete = idx < currentStep;
        final isActive = idx == currentStep;
        final solid = isComplete || isActive;
        return Semantics(
          label: 'Step ${idx + 1} of $totalSteps${isComplete ? ', done' : isActive ? ', current' : ''}',
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: solid ? AppColors.primary : AppColors.primarySoft,
            ),
            alignment: Alignment.center,
            child: isComplete
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : Text(
                    '${idx + 1}',
                    style: AppTypography.label.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isActive ? Colors.white : AppColors.primaryText,
                    ),
                  ),
          ),
        );
      }),
    );
  }
}
