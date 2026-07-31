import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The one "verified student/user" checkmark used everywhere a name is shown — profile, chat
/// header, connection cards, group members, activity roster, discovery. Keeping it in one place
/// means every surface stays visually consistent and updates together.
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Verified student',
      child: Icon(Icons.verified_rounded, color: AppColors.primary, size: size),
    );
  }
}
