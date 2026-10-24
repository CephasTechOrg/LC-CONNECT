part of '../screens/campus_hub_screen.dart';

/// Announcements panel — the most recent campus update, kept high on the page so
/// it is never pushed below the fold by the rest of the dashboard.
class _LatestUpdatesPanel extends StatelessWidget {
  final List<CampusPostSummary> updates;

  const _LatestUpdatesPanel({required this.updates});

  @override
  Widget build(BuildContext context) {
    final featured = updates.isEmpty ? null : updates.first;

    // Empty gets a quiet light row, not the navy feature panel: a saturated
    // gradient announcing "nothing yet" spends the page's strongest treatment
    // on the absence of content. The featured treatment is earned by an
    // actual update below.
    if (featured == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          0,
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.sheet),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: const Icon(
                  Icons.campaign_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Latest updates',
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'No campus announcements yet.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const _UpdatesSeeAll(onLight: true),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      child: Container(
        // Small top inset: the 48dp "See all" target already pads the header row.
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF264A6E), Color(0xFF1B3A5C)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x261B3A5C),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.campaign_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Latest updates',
                    style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const _UpdatesSeeAll(),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _FeaturedUpdateCard(post: featured),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdatesSeeAll extends ConsumerWidget {
  /// On the light empty-state row the label is brand blue, not white.
  final bool onLight;

  const _UpdatesSeeAll({this.onLight = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live count of new announcements since the user last opened the list — ticks up in real time.
    final count = ref.watch(announcementCountProvider);
    // `container` + `excludeSemantics`: without them this merged into the panel's node, so a
    // screen reader heard "Latest updates, See all, 2" as one run-on item.
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: count > 0 ? 'See all updates, $count new' : 'See all updates',
      child: InkWell(
        onTap: () => context.push('/home/updates'),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See all',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: onLight
                      ? AppColors.primaryText
                      : Colors.white.withValues(alpha: 0.9),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 7),
                Container(
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedUpdateCard extends StatelessWidget {
  final CampusPostSummary post;
  const _FeaturedUpdateCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: () => context.push('/home/posts/${post.id}'),
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: post.coverUrl != null
                    ? CachedNetworkImage(
                        key: const ValueKey('featured-update-cover'),
                        imageUrl: post.coverUrl!,
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => Image.asset(
                          campusSpotlightBackground,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Image.asset(
                        campusSpotlightBackground,
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (post.summary != null && post.summary!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        post.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _postAge(post.publishAt),
                      // 0.75, not 0.6: at 0.6 this 11px timestamp was 3.8:1 on the panel.
                      style: AppTypography.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _postAge(DateTime publishedAt) {
  final diff = DateTime.now().difference(publishedAt.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(publishedAt.toLocal());
}
