import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_states.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import 'campus_hub_screen.dart';

class CampusUpdatesScreen extends ConsumerStatefulWidget {
  const CampusUpdatesScreen({super.key});

  @override
  ConsumerState<CampusUpdatesScreen> createState() => _CampusUpdatesScreenState();
}

class _CampusUpdatesScreenState extends ConsumerState<CampusUpdatesScreen> {
  String _kind = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final kindParam = GoRouterState.of(context).uri.queryParameters['kind'];
    if (kindParam != null && kindParam != _kind) {
      _kind = kindParam;
    }
  }

  CampusPostsQuery get _query => CampusPostsQuery(
        kind: _kind == 'all' ? null : _kind,
      );

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(campusPostsProvider(_query));
    final filters = ['all', ...postKindLabels.keys];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SubpageHeader(title: 'Campus updates', onBack: () => context.pop()),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: filters.map((key) {
                  final label = key == 'all' ? 'All' : (postKindLabels[key] ?? key);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: label,
                      selected: _kind == key,
                      onTap: () => setState(() => _kind = key),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(campusPostsProvider(_query)),
                child: postsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => AppErrorState(
                    message: 'Could not load updates.',
                    onRetry: () => ref.invalidate(campusPostsProvider(_query)),
                  ),
                  data: (posts) {
                    if (posts.isEmpty) {
                      return const AppEmptyState(
                        icon: Icons.campaign_outlined,
                        title: 'No updates found',
                        subtitle: 'Try another filter or check back later.',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      itemCount: posts.length,
                      itemBuilder: (context, index) => CampusPostCard(
                        post: posts[index],
                        onTap: () => context.push('/home/posts/${posts[index].id}'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CampusOpportunitiesScreen extends ConsumerWidget {
  const CampusOpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const query = CampusPostsQuery(kind: 'opportunity');
    final postsAsync = ref.watch(campusPostsProvider(query));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _SubpageHeader(title: 'Opportunities', onBack: () => context.pop()),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(campusPostsProvider(query)),
                child: postsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => AppErrorState(
                    message: 'Could not load opportunities.',
                    onRetry: () => ref.invalidate(campusPostsProvider(query)),
                  ),
                  data: (posts) {
                    if (posts.isEmpty) {
                      return const AppEmptyState(
                        icon: Icons.work_outline,
                        title: 'No opportunities yet',
                        subtitle: 'Jobs, internships, and campus roles will appear here.',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      itemCount: posts.length,
                      itemBuilder: (context, index) => CampusPostCard(
                        post: posts[index],
                        onTap: () => context.push('/home/posts/${posts[index].id}'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CampusPostDetailScreen extends ConsumerWidget {
  final String postId;

  const CampusPostDetailScreen({super.key, required this.postId});

  Future<void> _launchExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(campusPostProvider(postId));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: postAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Column(
            children: [
              _SubpageHeader(title: 'Update', onBack: () => context.pop()),
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
              _SubpageHeader(title: postKindLabels[post.kind] ?? 'Update', onBack: () => context.pop()),
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

class _SubpageHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _SubpageHeader({required this.title, required this.onBack});

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
