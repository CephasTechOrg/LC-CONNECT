import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../models/campus_post.dart';

/// One row on the Announcements list. There are no per-announcement images, so the leading
/// thumbnail is a tinted icon placeholder — colored by category, same visual language as the
/// Opportunities cards. An unread dot marks announcements the user hasn't opened yet.
class CampusPostCard extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const CampusPostCard({super.key, required this.post, required this.onTap});

  static const _categoryStyles = <String, (Color, Color, IconData)>{
    'general': (AppColors.textMuted, AppColors.border, Icons.campaign_outlined),
    'academic': (AppColors.green, Color(0xFFDCFCE7), Icons.school_outlined),
    'campus': (AppColors.primary, AppColors.primarySoft, Icons.account_balance_outlined),
    'events': (Color(0xFF7C3AED), Color(0xFFF3E8FF), Icons.event_outlined),
    'safety': (Color(0xFFD97706), Color(0xFFFEF3C7), Icons.warning_amber_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final category = post.category ?? 'general';
    final (badgeColor, badgeBg, icon) = _categoryStyles[category] ?? _categoryStyles['general']!;
    final categoryLabel = announcementCategoryLabels[category] ?? 'General';
    final dateLabel = DateFormat('MMM d').format(post.publishAt.toLocal());

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(color: Color(0x0A111827), blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon placeholder — stands in for an image (announcements have no photo).
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(13)),
                  child: Icon(icon, color: badgeColor, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Unread dot — cleared once the user opens this announcement.
                          if (!post.read) ...[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(8)),
                            child: Text(
                              categoryLabel,
                              style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor),
                            ),
                          ),
                          const Spacer(),
                          Text(dateLabel, style: GoogleFonts.dmSans(fontSize: 11.5, color: AppColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                          fontSize: 14.5,
                          // Read titles de-emphasize; unread stay bold + dark so new ones stand out.
                          fontWeight: post.read ? FontWeight.w600 : FontWeight.w700,
                          color: post.read ? AppColors.textMid : AppColors.textDark,
                        ),
                      ),
                      if (post.summary != null && post.summary!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          post.summary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
