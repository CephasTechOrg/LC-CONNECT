import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';

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
              color: isComplete ? AppColors.primary : AppColors.border,
            ),
          );
        }
        final idx = i ~/ 2;
        final isComplete = idx < currentStep;
        final isActive = idx == currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isComplete || isActive ? AppColors.primary : Colors.white,
            border: Border.all(
              color: isComplete || isActive ? AppColors.primary : AppColors.border,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: isComplete
              ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
              : Text(
                  '${idx + 1}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : AppColors.textMuted,
                  ),
                ),
        );
      }),
    );
  }
}

class OnboardingLabel extends StatelessWidget {
  final String text;
  final bool optional;
  const OnboardingLabel(this.text, {super.key, this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMid,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Text(
              'optional',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class OnboardingChipGrid extends StatelessWidget {
  final List<String> options;
  final List<String>? optionKeys;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool highlight;

  const OnboardingChipGrid({
    super.key,
    required this.options,
    this.optionKeys,
    required this.selected,
    required this.onToggle,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(options.length, (i) {
        final key = optionKeys?[i] ?? options[i];
        final label = options[i];
        final isOn = selected.contains(key);
        return GestureDetector(
          onTap: () => onToggle(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isOn
                  ? (highlight ? AppColors.primary : AppColors.primarySoft)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOn ? AppColors.primary : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                color: isOn
                    ? (highlight ? Colors.white : AppColors.primary)
                    : AppColors.textMid,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class OnboardingBottomBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool isLoading;
  final bool canProceed;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const OnboardingBottomBar({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.isLoading,
    required this.canProceed,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (step > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: isLoading ? null : onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: (canProceed && !isLoading) ? onNext : null,
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isLast ? 'Finish Setup' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}
