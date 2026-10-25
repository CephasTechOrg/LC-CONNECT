import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/campus_publishing_provider.dart';
import '../widgets/campus_subpage_header.dart';

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
              label: Text('New post', style: AppTypography.body.copyWith(fontWeight: FontWeight.w700)),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The same header as Announcements and Opportunities — this is their authoring side.
            CampusSubpageHeader(
              title: 'My campus posts',
              subtitle: 'Drafts, published and archived',
              onBack: () => context.pop(),
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
                      subtitle:
                          capabilities.reason ??
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
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.gutter,
                            AppSpacing.sm,
                            AppSpacing.gutter,
                            100,
                          ),
                          itemCount: posts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Published')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e, fallback: 'Could not publish'))));
      }
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref, AuthorCampusPost post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this post?'),
        content: Text(
          '“${post.title}” will be taken off Campus Hub. It stays here as archived, so nothing is lost.',
        ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Removed from Campus Hub')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e, fallback: 'Could not archive'))));
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
    final summary = post.summary;
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.xs, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 48dp tall so the Publish pill and the menu keep full tap targets without padding the
          // card's top edge.
          SizedBox(
            height: kMinInteractiveDimension,
            child: Row(
              children: [
                _StatusPill(status: post.status),
                const SizedBox(width: AppSpacing.sm),
                Text(kind, style: AppTypography.label.copyWith(color: AppColors.textMuted)),
                const Spacer(),
                if (post.isDraft) _PublishPill(onTap: onPublish),
                if (!_archived) _menu() else const SizedBox(width: AppSpacing.md),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    // Archived posts are history: still readable, no longer competing.
                    color: _archived ? AppColors.textMid : AppColors.textDark,
                  ),
                ),
                if (summary != null && summary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menu() {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textMuted),
      onSelected: (v) => v == 'edit' ? onEdit() : onRemove(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Edit')),
        const PopupMenuItem(value: 'remove', child: Text('Remove from Hub')),
      ],
    );
  }
}

/// A draft's one action — a filled pill, the same treatment as Join and Accept.
class _PublishPill extends StatelessWidget {
  final VoidCallback onTap;
  const _PublishPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: 'Publish',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: AppRadii.all(AppRadii.full),
              ),
              child: Text(
                'Publish',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  // Colour only where it means something: green for live, the soft brand tint for a draft,
  // grey for archived. Text shades are the AA ones; the old green label was ~2.4:1.
  static const _liveText = Color(0xFF15803D);
  static const _liveTint = Color(0xFFDCFCE7);
  static const _quietTint = Color(0xFFEEF2F6);

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, String label) = switch (status) {
      'published' => (_liveText, _liveTint, 'Published'),
      'draft' => (AppColors.primaryText, AppColors.primarySoft, 'Draft'),
      'archived' => (AppColors.textMuted, _quietTint, 'Archived'),
      _ => (AppColors.textMuted, _quietTint, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadii.all(AppRadii.full)),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
