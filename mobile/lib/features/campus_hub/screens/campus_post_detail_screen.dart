import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_states.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../widgets/campus_post_style.dart';
import '../widgets/campus_subpage_header.dart';

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
        child: postAsync.when(
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
              CampusSubpageHeader(title: postKindLabels[post.kind] ?? 'Post', onBack: () => context.pop()),
              Expanded(child: _PostBody(post: post, onLaunch: _launchExternal)),
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
    final categoryLabel = categoryLabelsForKind(post.kind)[post.category ?? ''] ??
        (post.category != null && post.category!.isNotEmpty
            ? '${post.category![0].toUpperCase()}${post.category!.substring(1)}'
            : postKindLabels[post.kind] ?? 'Post');
    final isPartner = post.isEmployerPartner || post.isBlueprintBond;

    final deadline = post.expiresAt?.toLocal();
    final daysLeft = deadline?.difference(DateTime.now()).inDays;
    final closingSoon = daysLeft != null && daysLeft <= 3;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
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
                      label: isPartner ? 'Employer Partner' : 'Campus Opportunity',
                      color: isPartner ? AppColors.primary : AppColors.textMuted,
                      background: isPartner ? AppColors.primarySoft : AppColors.background,
                    ),
                  if (post.isUrgent)
                    const CampusBadge(
                      label: 'Urgent',
                      color: Color(0xFFDC2626),
                      background: Color(0xFFFEE2E2),
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
          style: GoogleFonts.dmSans(
            fontSize: 22,
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
              style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
        ),
        if (deadline != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: closingSoon ? const Color(0xFFFEE2E2) : AppColors.primarySoft,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 14,
                  color: closingSoon ? const Color(0xFFDC2626) : AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  closingSoon
                      ? 'Closes ${DateFormat('MMM d').format(deadline)} · ${daysLeft <= 0 ? 'today' : daysLeft == 1 ? '1 day left' : '$daysLeft days left'}'
                      : 'Deadline: ${DateFormat('MMM d, y').format(deadline)}',
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: closingSoon ? const Color(0xFFDC2626) : AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Container(height: 1, color: AppColors.border),
        const SizedBox(height: 20),
        Text(
          post.body,
          style: GoogleFonts.dmSans(fontSize: 15, height: 1.55, color: AppColors.textMid),
        ),
        if (post.externalUrl != null && post.externalUrl!.isNotEmpty) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => onLaunch(post.externalUrl!),
              icon: Icon(isOpportunity ? Icons.launch_rounded : Icons.open_in_new_rounded, size: 18),
              label: Text(
                isOpportunity ? 'Apply now' : 'Open link',
                style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
