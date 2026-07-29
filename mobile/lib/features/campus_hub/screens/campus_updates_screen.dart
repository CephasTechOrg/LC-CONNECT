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
import '../widgets/campus_post_card.dart';

class CampusUpdatesScreen extends ConsumerStatefulWidget {
  const CampusUpdatesScreen({super.key});

  @override
  ConsumerState<CampusUpdatesScreen> createState() => _CampusUpdatesScreenState();
}

class _CampusUpdatesScreenState extends ConsumerState<CampusUpdatesScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Opening the list clears the "new announcements" badge (deferred — can't mutate a provider
    // during the first build).
    Future.microtask(() => ref.read(announcementCountProvider.notifier).markSeen());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Load the next page a little before the very bottom for a seamless feel.
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      ref.read(announcementsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(announcementsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SubpageHeader(title: 'Announcements', onBack: () => context.pop()),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(announcementsProvider),
                child: async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => AppErrorState(
                    message: 'Could not load announcements.',
                    onRetry: () => ref.invalidate(announcementsProvider),
                  ),
                  data: (data) {
                    if (data.items.isEmpty) {
                      return const AppEmptyState(
                        icon: Icons.campaign_outlined,
                        title: 'No announcements yet',
                        subtitle: 'Official campus announcements will appear here.',
                      );
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      itemCount: data.items.length + (data.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= data.items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final post = data.items[index];
                        return CampusPostCard(
                          post: post,
                          onTap: () => context.push('/home/posts/${post.id}'),
                        );
                      },
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

    // Reading an announcement takes one off the "new" badge (once per open).
    final post = postAsync.asData?.value;
    if (!_countedAsRead && post != null && post.kind == 'announcement') {
      _countedAsRead = true;
      Future.microtask(() => ref.read(announcementCountProvider.notifier).decrement());
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: postAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Column(
            children: [
              _SubpageHeader(title: 'Post', onBack: () => context.pop()),
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
              _SubpageHeader(title: postKindLabels[post.kind] ?? 'Post', onBack: () => context.pop()),
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
