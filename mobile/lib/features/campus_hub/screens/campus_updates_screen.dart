import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
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
    // Read state is per-item: an announcement counts as read only when the user opens *that*
    // announcement (see the detail screen). Browsing the list does not mark everything read.
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
    final selectedCategory = ref.watch(announcementCategoryFilterProvider);
    // The live unread badge (server-backed, same counter as the home panel) — richer than a
    // plain header, and it's already flowing through the app so it costs nothing extra to show.
    final unread = ref.watch(announcementCountProvider);
    final total = async.asData?.value.total;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AnnouncementsHero(onBack: () => context.pop(), total: total, unread: unread),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: 'All',
                      selected: selectedCategory == null,
                      onTap: () => ref.read(announcementCategoryFilterProvider.notifier).set(null),
                    ),
                  ),
                  for (final entry in announcementCategoryLabels.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppFilterChip(
                        label: entry.value,
                        selected: selectedCategory == entry.key,
                        onTap: () => ref.read(announcementCategoryFilterProvider.notifier).set(entry.key),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
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
                      itemCount: data.items.length + 1, // +1 for the trailing footer/spinner
                      itemBuilder: (context, index) {
                        if (index == data.items.length) {
                          return _AnnouncementsFooter(
                            loadingMore: data.loadingMore,
                            shown: data.items.length,
                            total: data.total,
                          );
                        }
                        final post = data.items[index];
                        return CampusPostCard(
                          post: post,
                          onTap: () {
                            // Clear its unread dot immediately; the detail screen + counter handle
                            // the server-side read + badge.
                            ref.read(announcementsProvider.notifier).markRead(post.id);
                            context.push('/home/posts/${post.id}');
                          },
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

/// Header — same navy tone as the home "Latest updates" panel (so this still reads as one
/// designed surface, not a plain white page), pared down to just back + title + a live stat
/// line. No extra icon badge or shadow — kept simple on purpose.
class _AnnouncementsHero extends StatelessWidget {
  final VoidCallback onBack;
  final int? total;
  final int unread;
  const _AnnouncementsHero({required this.onBack, required this.total, required this.unread});

  String get _subtitle {
    if (total == null) return 'Official campus announcements';
    final countLabel = '$total announcement${total == 1 ? '' : 's'}';
    return unread > 0 ? '$countLabel · $unread new' : countLabel;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1B3A5C),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Announcements',
                  style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  style: GoogleFonts.dmSans(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementsFooter extends StatelessWidget {
  final bool loadingMore;
  final int shown;
  final int total;
  const _AnnouncementsFooter({required this.loadingMore, required this.shown, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: loadingMore
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(
                'Showing $shown of $total announcement${total == 1 ? '' : 's'}',
                style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
              ),
      ),
    );
  }
}
