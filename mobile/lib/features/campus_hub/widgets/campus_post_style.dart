import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// (accent color, tinted background, icon) for a post's category — shared by both list cards and
/// the detail screen so a given category always reads the same everywhere, and so the mapping
/// only exists once instead of being copy-pasted per screen.
typedef CampusCategoryStyle = (Color color, Color background, IconData icon);

const announcementCategoryStyles = <String, CampusCategoryStyle>{
  'general': (AppColors.textMuted, AppColors.border, Icons.campaign_outlined),
  'academic': (AppColors.green, Color(0xFFDCFCE7), Icons.school_outlined),
  'campus': (AppColors.primary, AppColors.primarySoft, Icons.account_balance_outlined),
  'events': (Color(0xFF7C3AED), Color(0xFFF3E8FF), Icons.event_outlined),
  'safety': (Color(0xFFD97706), Color(0xFFFEF3C7), Icons.warning_amber_rounded),
};

const opportunityCategoryStyles = <String, CampusCategoryStyle>{
  'internship': (Color(0xFF2563EB), Color(0xFFE0EDFF), Icons.school_outlined),
  'job': (Color(0xFFD97706), Color(0xFFFEF3C7), Icons.work_outline_rounded),
  'volunteer': (Color(0xFF16A34A), Color(0xFFDCFCE7), Icons.favorite_outline_rounded),
  'leadership': (Color(0xFF7C3AED), Color(0xFFF3E8FF), Icons.emoji_events_outlined),
};

CampusCategoryStyle campusCategoryStyle(String kind, String? category) {
  if (kind == 'opportunity') {
    return opportunityCategoryStyles[category] ??
        (AppColors.primary, AppColors.primarySoft, Icons.work_outline_rounded);
  }
  return announcementCategoryStyles[category] ?? announcementCategoryStyles['general']!;
}

/// A small pill badge — used for category, source, and type labels across both list cards and
/// the detail screen.
class CampusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  const CampusBadge({super.key, required this.label, required this.color, required this.background, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(7)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
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
