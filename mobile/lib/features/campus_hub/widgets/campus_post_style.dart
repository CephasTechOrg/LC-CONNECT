import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// (accent color, tinted background, icon) for a post's category — shared by list cards and the
/// detail screen so a category reads the same everywhere.
///
/// Every category shares one tint: brand blue on its soft wash. Categories used to each carry a
/// colour (green Academic, purple Events, amber Safety…), and a page of them read as colours
/// competing rather than as one list. Colour is kept for things that *mean* something — unread,
/// a deadline closing — and categories are told apart by their icon and their label instead.
typedef CampusCategoryStyle = (Color color, Color background, IconData icon);

const announcementCategoryIcons = <String, IconData>{
  'general': Icons.campaign_outlined,
  'academic': Icons.school_outlined,
  'campus': Icons.account_balance_outlined,
  'events': Icons.event_outlined,
  'safety': Icons.health_and_safety_outlined,
};

const opportunityCategoryIcons = <String, IconData>{
  'internship': Icons.school_outlined,
  'job': Icons.work_outline_rounded,
  'volunteer': Icons.favorite_outline_rounded,
  'leadership': Icons.emoji_events_outlined,
};

CampusCategoryStyle campusCategoryStyle(String kind, String? category) {
  final icon = kind == 'opportunity'
      ? opportunityCategoryIcons[category] ?? Icons.work_outline_rounded
      : announcementCategoryIcons[category] ?? Icons.campaign_outlined;
  return (AppColors.primaryText, AppColors.primarySoft, icon);
}

/// A small pill badge — used for category, source, and type labels across both list cards and
/// the detail screen.
class CampusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  const CampusBadge({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
