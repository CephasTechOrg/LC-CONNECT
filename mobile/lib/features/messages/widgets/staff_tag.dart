import 'package:flutter/material.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// A small "Staff" marker beside a name in the inbox and the new-message results.
///
/// Stands in for the full position title, which does not fit beside a name on a phone; the chat
/// header spells it out.
class StaffTag extends StatelessWidget {
  const StaffTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.all(AppRadii.full),
      ),
      child: Text(
        'Staff',
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.primaryText,
        ),
      ),
    );
  }
}
