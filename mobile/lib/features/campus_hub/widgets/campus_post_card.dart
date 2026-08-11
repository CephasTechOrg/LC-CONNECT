import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../models/campus_post.dart';
import 'campus_post_style.dart';

/// One row on the Announcements list. There are no per-announcement images, so the leading
/// thumbnail is a tinted icon placeholder — colored by category, same visual language as the
/// Opportunities cards. An unread dot marks announcements the user hasn't opened yet.
class CampusPostCard extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const CampusPostCard({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final category = post.category ?? 'general';
    final (badgeColor, badgeBg, icon) = campusCategoryStyle('announcement', category);
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
                          CampusBadge(label: categoryLabel, color: badgeColor, background: badgeBg),
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
