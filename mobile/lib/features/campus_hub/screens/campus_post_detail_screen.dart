import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_states.dart';
import '../data/opportunity_format.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../widgets/campus_post_image_pager.dart';
import '../widgets/campus_post_style.dart';
import '../widgets/campus_subpage_header.dart';
import '../widgets/link_preview_card.dart';
import '../../../shared/util/caching.dart';

class CampusPostDetailScreen extends ConsumerStatefulWidget {
  final String postId;

  const CampusPostDetailScreen({super.key, required this.postId});

  @override
  ConsumerState<CampusPostDetailScreen> createState() => _CampusPostDetailScreenState();
}

class _CampusPostDetailScreenState extends ConsumerState<CampusPostDetailScreen> {
  bool _countedAsRead = false;

  String get postId => widget.postId;

  Future<void> _launchExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final postAsync = ref.watch(campusPostProvider(postId));

    // Reading an announcement marks that one read on the server + takes it off the badge (once).
    final post = postAsync.asData?.value;
    if (!_countedAsRead && post != null && post.kind == 'announcement') {
      _countedAsRead = true;
      Future.microtask(() => ref.read(announcementCountProvider.notifier).readOne(postId));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: postAsync.cached(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Column(
            children: [
              CampusSubpageHeader(title: 'Post', onBack: () => context.pop()),
              Expanded(
                child: AppErrorState(
                  message: 'Could not load this update.',
                  onRetry: () => ref.invalidate(campusPostProvider(postId)),
                ),
              ),
            ],
          ),
          data: (post) => Column(
            children: [
              CampusSubpageHeader(
                title: postKindLabels[post.kind] ?? 'Post',
                onBack: () => context.pop(),
              ),
              Expanded(
                child: _PostBody(post: post, onLaunch: _launchExternal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostBody extends StatelessWidget {
  final CampusPost post;
  final Future<void> Function(String url) onLaunch;
  const _PostBody({required this.post, required this.onLaunch});

  @override
  Widget build(BuildContext context) {
    final isOpportunity = post.kind == 'opportunity';
    final (accent, accentBg, icon) = campusCategoryStyle(post.kind, post.category);
    final categoryLabel =
        categoryLabelsForKind(post.kind)[post.category ?? ''] ??
        (post.category != null && post.category!.isNotEmpty
            ? '${post.category![0].toUpperCase()}${post.category!.substring(1)}'
            : postKindLabels[post.kind] ?? 'Post');
    final isPartner = post.isEmployerPartner || post.isBlueprintBond;

    final deadline = post.expiresAt?.toLocal();
    final deadlineText = deadlineLabel(deadline, post.category);
    final closingSoon = deadlineText.urgent;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        if (post.images.isNotEmpty) ...[
          CampusPostImagePager(images: post.images, postId: post.id),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: accentBg, borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  CampusBadge(label: categoryLabel, color: accent, background: accentBg),
                  if (isOpportunity)
                    CampusBadge(
                      label: isPartner ? 'Employer partner' : 'Campus opportunity',
                      color: isPartner ? AppColors.primaryText : AppColors.textMuted,
                      background: isPartner ? AppColors.primarySoft : AppColors.background,
                    ),
                  if (post.isUrgent)
                    const CampusBadge(
                      label: 'Urgent',
                      // Red because urgent *is* an alert; the deeper shade passes AA on the tint.
                      color: AppColors.errorText,
                      background: AppColors.errorSoft,
                      icon: Icons.priority_high_rounded,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          post.title,
          style: AppTypography.titleLarge.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
            letterSpacing: -0.3,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.event_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 5),
            Text(
              DateFormat('EEEE, MMM d').format(post.publishAt.toLocal()),
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        if (deadline != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              // Amber, as on the Opportunities list: a near deadline is a warning, not an error.
              color: closingSoon ? _warningTint : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: closingSoon ? _warning : AppColors.primaryText,
                ),
                const SizedBox(width: 6),
                Text(
                  // The same words as the card: one deadline, one way of saying it.
                  deadlineText.text,
                  style: AppTypography.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: closingSoon ? _warning : AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 20),
        // Opportunities are title + summary (+ link). When body was auto-filled from summary,
        // show the summary once (not a duplicated body block).
        if (_opportunityBodyRedundant(post))
          Text(
            post.summary!,
            style: AppTypography.bodyLarge.copyWith(height: 1.55, color: AppColors.textMid),
          )
        else
          Text(
            post.body,
            style: AppTypography.bodyLarge.copyWith(height: 1.55, color: AppColors.textMid),
          ),
        if (post.externalUrl != null && post.externalUrl!.isNotEmpty) ...[
          const SizedBox(height: 24),
          LinkPreviewCard(
            url: post.externalUrl!,
            preview: post.linkPreview,
            compact: false,
            onTap: () => onLaunch(post.externalUrl!),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => onLaunch(post.externalUrl!),
              icon: Icon(
                isOpportunity ? Icons.launch_rounded : Icons.open_in_new_rounded,
                size: 18,
              ),
              label: Text(
                isOpportunity ? 'Apply now' : 'Open link',
                style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

bool _opportunityBodyRedundant(CampusPost post) {
  if (post.kind != 'opportunity') return false;
  final summary = post.summary?.trim() ?? '';
  final body = post.body.trim();
  return summary.isNotEmpty && body == summary;
}

const _warning = AppColors.warning;
const _warningTint = AppColors.warningSoft;
