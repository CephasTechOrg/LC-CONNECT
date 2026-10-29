import 'package:flutter/material.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../data/opportunity_format.dart';
import '../models/campus_post.dart';
import 'campus_post_style.dart';
import 'link_preview_card.dart';
import '../../../shared/widgets/app_card.dart';

/// Opportunities list card — badges → title → summary → link preview → meta footer.
class OpportunityCard extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const OpportunityCard({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (badgeColor, badgeBg, icon) = campusCategoryStyle('opportunity', post.category);
    final isPartner = post.isEmployerPartner || post.isBlueprintBond;
    // Type, source and date as one quiet line, the same as an announcement's meta line. These
    // were two coloured pills (the type in its category colour, the source in blue or grey) beside
    // a separate date — three treatments for three facts of equal weight.
    final meta = [
      opportunityTypeLabel(post.category),
      isPartner ? 'Employer partner' : 'Campus',
      postedLabel(post.publishAt),
    ].join(' · ');

    final deadline = deadlineLabel(post.expiresAt, post.category);
    final closingSoon = deadline.urgent;
    final hasLink = post.externalUrl != null && post.externalUrl!.trim().isNotEmpty;
    final summary = post.summary?.trim();

    // The shared card surface (borderless, soft shadow), same as Home and Activities.
    return AppCard(
      onTap: onTap,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Icon(icon, color: badgeColor, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                  if (summary != null && summary.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      if (isPartner) ...[
                        const Icon(Icons.verified_rounded, size: 13, color: AppColors.primaryText),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          meta,
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
          ],
        ),
        if (hasLink) ...[
          const SizedBox(height: 10),
          LinkPreviewCard(url: post.externalUrl!, preview: post.linkPreview, compact: true),
        ],
        const SizedBox(height: AppSpacing.sm),
        // Starts under the title, not under the icon, so the text edge runs straight down the card.
        Padding(
          padding: const EdgeInsets.only(left: 56 + 12),
          child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 14,
              color: closingSoon ? _closingAmber : AppColors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              deadline.text,
              style: AppTypography.label.copyWith(
                fontWeight: closingSoon ? FontWeight.w700 : FontWeight.w500,
                color: closingSoon ? _closingAmber : AppColors.textMuted,
              ),
            ),
            const Spacer(),
            Text(
              hasLink ? 'Apply' : 'Details',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primaryText),
          ],
        ),
        ),
        ],
      ),
    );
  }
}

/// "Closes Oct 28" when three days or fewer are left: amber, because a deadline is a warning, not
/// an error. Red is kept for errors. 5.0:1 on white.
const _closingAmber = AppColors.warning;
