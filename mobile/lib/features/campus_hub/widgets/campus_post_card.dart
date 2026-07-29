import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../models/campus_post.dart';

class CampusPostCard extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const CampusPostCard({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final kindLabel = postKindLabels[post.kind] ?? post.kind;
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _KindChip(label: kindLabel),
                    if (post.isUrgent || post.isImportant) ...[
                      const SizedBox(width: 8),
                      _PriorityChip(urgent: post.isUrgent),
                    ],
                    const Spacer(),
                    Text(
                      dateLabel,
                      style: GoogleFonts.dmSans(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  post.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                if (post.summary != null && post.summary!.isNotEmpty) ...[
                  const SizedBox(height: 4),
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
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final String label;
  const _KindChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  final bool urgent;
  const _PriorityChip({required this.urgent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xFFFFF1F2) : AppColors.primaryPale,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        urgent ? 'Urgent' : 'Important',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: urgent ? AppColors.error : AppColors.primary,
        ),
      ),
    );
  }
}
