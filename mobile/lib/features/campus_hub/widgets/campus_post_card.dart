import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../models/campus_post.dart';
import 'campus_post_style.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';

/// One row on the Announcements list. A 56dp cover thumbnail when the post has photos (real
/// content first); otherwise the category icon on the shared blue tint. An unread dot marks
/// announcements not yet opened.
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.sm),
      // The shared card surface (borderless, soft shadow), same as Home and Activities.
      child: AppCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverThumb(
              coverUrl: post.coverUrl,
              badgeBg: badgeBg,
              badgeColor: badgeColor,
              icon: icon,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The title leads, on two lines: a one-line title cut most announcements mid-phrase
                  // ("Spring registration opens Mon…"), and the title is the whole point of a row.
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
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
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  // Category and date as one quiet line — hierarchy by position and weight, not by
                  // a coloured pill per category. The dot is the one colour, and it means "unread".
                  Row(
                    children: [
                      if (!post.read) ...[
                        Semantics(
                          label: 'Unread',
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          '$categoryLabel · $dateLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
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
    );
  }
}

class _CoverThumb extends StatelessWidget {
  final String? coverUrl;
  final Color badgeBg;
  final Color badgeColor;
  final IconData icon;

  const _CoverThumb({
    required this.coverUrl,
    required this.badgeBg,
    required this.badgeColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (coverUrl == null) {
      return Container(
        key: const ValueKey('campus-post-icon'),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: badgeColor, size: 26),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: CachedNetworkImage(
        key: const ValueKey('campus-post-cover'),
        imageUrl: coverUrl!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Container(
          width: 56,
          height: 56,
          color: badgeBg,
          child: Icon(icon, color: badgeColor, size: 26),
        ),
      ),
    );
  }
}
