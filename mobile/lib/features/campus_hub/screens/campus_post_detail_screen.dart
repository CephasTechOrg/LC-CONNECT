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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Text(
                      post.title,
                      style: GoogleFonts.dmSans(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('EEEE, MMM d · h:mm a').format(post.publishAt.toLocal()),
                      style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
                    ),
                    if (post.expiresAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Deadline: ${DateFormat('MMM d, y').format(post.expiresAt!.toLocal())}',
                        style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      post.body,
                      style: GoogleFonts.dmSans(fontSize: 15, height: 1.5, color: AppColors.textMid),
                    ),
                    if (post.externalUrl != null && post.externalUrl!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _launchExternal(post.externalUrl!),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Open link'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
