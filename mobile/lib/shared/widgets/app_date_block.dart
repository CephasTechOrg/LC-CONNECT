import 'package:flutter/material.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../util/app_date_format.dart';

/// "OCT / 26" on a pale-blue tile — how an activity's date is shown everywhere, so a student
/// recognises an activity at a glance whether it is on Home or in the Activities list.
class AppDateBlock extends StatelessWidget {
  final DateTime date;

  /// The student has joined. Shown as a check on the corner of the date rather than a pill beside
  /// the title: on a 320dp phone a pill cost the title half its width.
  final bool going;

  const AppDateBlock({super.key, required this.date, this.going = false});

  static const size = 54.0;

  @override
  Widget build(BuildContext context) {
    final block = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.all(AppRadii.lg),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppDateFormat.month(date).toUpperCase(),
            style: AppTypography.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AppDateFormat.dayOfMonth(date),
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
    if (!going) return block;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        block,
        Positioned(
          top: -5,
          right: -5,
          child: Semantics(
            container: true,
            label: "You're going",
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
