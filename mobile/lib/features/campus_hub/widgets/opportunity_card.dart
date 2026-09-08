import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../models/campus_post.dart';
import 'campus_post_style.dart';
import 'link_preview_card.dart';

/// Opportunities list card — badges → title → summary → link preview → meta footer.
class OpportunityCard extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const OpportunityCard({super.key, required this.post, required this.onTap});

  static String typeLabel(String category) =>
      opportunityCategoryLabels[category] ??
      (category.isNotEmpty ? '${category[0].toUpperCase()}${category.substring(1)}' : 'Opportunity');

  @override
  Widget build(BuildContext context) {
    final (badgeColor, badgeBg, icon) = campusCategoryStyle('opportunity', post.category);
    final type = typeLabel(post.category ?? '');
    final isPartner = post.isEmployerPartner || post.isBlueprintBond;
    final sourceLabel = isPartner ? 'Employer Partner' : 'Campus';
    final sourceColor = isPartner ? AppColors.primary : AppColors.textMuted;
    final sourceBg = isPartner ? AppColors.primarySoft : AppColors.background;

    final deadline = post.expiresAt;
    final daysLeft = deadline?.toLocal().difference(DateTime.now()).inDays;
    final closingSoon = daysLeft != null && daysLeft <= 3;
    final hasLink = post.externalUrl != null && post.externalUrl!.trim().isNotEmpty;
    final summary = post.summary?.trim();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(11)),
                    child: Icon(icon, color: badgeColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CampusBadge(label: type, color: badgeColor, background: badgeBg),
                        CampusBadge(label: sourceLabel, color: sourceColor, background: sourceBg),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('MMM d').format(post.publishAt.toLocal()),
                    style: GoogleFonts.dmSans(fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                  height: 1.25,
                  letterSpacing: -0.2,
                ),
              ),
              if (summary != null && summary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid, height: 1.35),
                ),
              ],
              if (hasLink) ...[
                const SizedBox(height: 10),
                LinkPreviewCard(
                  url: post.externalUrl!,
                  preview: post.linkPreview,
                  compact: true,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (deadline != null) ...[
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: closingSoon ? const Color(0xFFDC2626) : AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Closes ${DateFormat('MMM d').format(deadline.toLocal())}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: closingSoon ? FontWeight.w700 : FontWeight.w500,
                        color: closingSoon ? const Color(0xFFDC2626) : AppColors.textMuted,
                      ),
                    ),
                  ] else
                    Text(
                      'Open role',
                      style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
                    ),
                  const Spacer(),
                  Text(
                    hasLink ? 'Apply' : 'Details',
                    style: GoogleFonts.dmSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
