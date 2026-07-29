import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_states.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/campus_publishing_provider.dart';

class MyCampusPostsScreen extends ConsumerWidget {
  const MyCampusPostsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(publishingCapabilitiesProvider);
    final postsAsync = ref.watch(myCampusPostsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: caps.asData?.value.canPublish == true
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/home/my-posts/new'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text('New post', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      'My campus posts',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: caps.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => AppErrorState(
                  message: 'Could not check publishing access.',
                  onRetry: () => ref.invalidate(publishingCapabilitiesProvider),
                ),
                data: (capabilities) {
                  if (!capabilities.canPublish) {
                    return AppEmptyState(
                      icon: Icons.lock_outline,
                      title: 'Publishing not available',
                      subtitle: capabilities.reason ??
                          'A verified campus position is required to publish.',
                    );
                  }
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async => ref.invalidate(myCampusPostsProvider),
                    child: postsAsync.when(
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (_, _) => AppErrorState(
                        message: 'Could not load your posts.',
                        onRetry: () => ref.invalidate(myCampusPostsProvider),
                      ),
                      data: (posts) {
                        if (posts.isEmpty) {
                          return AppEmptyState(
                            icon: Icons.campaign_outlined,
                            title: 'No posts yet',
                            subtitle: 'Create an update or opportunity for campus.',
                            actionLabel: 'New post',
                            onAction: () => context.push('/home/my-posts/new'),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                          itemCount: posts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => _AuthorPostTile(
                            post: posts[index],
                            onEdit: () => context.push('/home/my-posts/new', extra: posts[index]),
                            onPublish: () => _publish(context, ref, posts[index]),
                            onRemove: () => _archive(context, ref, posts[index]),
                            onOpen: posts[index].isPublished
                                ? () => context.push('/home/posts/${posts[index].id}')
                                : null,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref, AuthorCampusPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish this post?'),
        content: Text(
          post.priority == 'important'
              ? '“${post.title}” may notify the campus audience.'
              : '“${post.title}” will appear in Campus Hub for its audience.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(campusPublishingServiceProvider).publishPost(post.id);
      _invalidateFeeds(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Published')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e, fallback: 'Could not publish'))),
        );
      }
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref, AuthorCampusPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this post?'),
        content: Text('“${post.title}” will be taken off Campus Hub. It stays here as archived, so nothing is lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(campusPublishingServiceProvider).archivePost(post.id);
      _invalidateFeeds(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from Campus Hub')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(e, fallback: 'Could not archive'))),
        );
      }
    }
  }

  void _invalidateFeeds(WidgetRef ref) {
    ref.invalidate(myCampusPostsProvider);
    ref.invalidate(campusHubOverviewProvider);
    ref.invalidate(campusPostsProvider);
  }
}

class _AuthorPostTile extends StatelessWidget {
  final AuthorCampusPost post;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onRemove;
  final VoidCallback? onOpen;

  const _AuthorPostTile({
    required this.post,
    required this.onEdit,
    required this.onPublish,
    required this.onRemove,
    this.onOpen,
  });

  bool get _archived => post.status == 'archived';

  @override
  Widget build(BuildContext context) {
    final kind = postKindLabels[post.kind] ?? post.kind;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusPill(status: post.status),
                  const SizedBox(width: 8),
                  Text(
                    kind,
                    style: GoogleFonts.dmSans(
                        fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  ),
                  const Spacer(),
                  if (post.isDraft)
                    TextButton(
                      onPressed: onPublish,
                      style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                      child: Text('Publish',
                          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ),
                  if (!_archived) _menu(),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 2, right: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: GoogleFonts.dmSans(
                          fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textDark),
                    ),
                    if (post.summary != null && post.summary!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        post.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid),
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

  Widget _menu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textMuted),
      onSelected: (v) => v == 'edit' ? onEdit() : onRemove(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'remove', child: Text('Remove from Hub')),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String label) = switch (status) {
      'published' => (AppColors.green, AppColors.green.withValues(alpha: 0.12), 'Published'),
      'draft' => (AppColors.primary, AppColors.primarySoft, 'Draft'),
      'archived' => (AppColors.textMuted, AppColors.border, 'Archived'),
      _ => (AppColors.textMuted, AppColors.border, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
