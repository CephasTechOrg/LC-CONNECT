import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

/// Shared back-arrow + title header for Campus Hub subpages (Announcements, Opportunities, post
/// detail, etc.) — kept in one place so they stay visually consistent.
class CampusSubpageHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const CampusSubpageHeader({super.key, required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
