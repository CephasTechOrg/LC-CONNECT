part of '../screens/campus_hub_screen.dart';

/// How many announcements Home lists. The overview returns up to five; three keeps the section
/// shorter than a screen while still showing "there is more than one thing going on".
const _homeUpdateCount = 3;

/// "Latest updates" heading, with the live new-announcement count on its action.
class _LatestUpdatesHeader extends ConsumerWidget {
  const _LatestUpdatesHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live count of new announcements since the user last opened the list — ticks up in real time.
    final count = ref.watch(announcementCountProvider);
    return _SectionHeader(
      title: 'Latest updates',
      newCount: count,
      onAction: () => context.push('/home/updates'),
    );
  }
}

/// The newest announcements as one light, grouped list.
///
/// This used to be a navy gradient panel holding a single post. On a dashboard where the urgent
/// alert is red and an open attendance session is solid brand blue, a third saturated block for
/// routine news meant nothing on the page read as *more* important than anything else — the
/// same "emphasis follows urgency" problem report #18 fixed for the Blueprint prompt. It also
/// showed one post of the five the overview already returns.
///
/// Now: a white card, newest first, the lead item given a larger thumbnail and its summary. The
/// row style mirrors the Announcements screen's cards (category icon, unread dot, read titles
/// de-emphasised), so an update looks the same on Home as it does one tap later.
class _LatestUpdatesList extends StatelessWidget {
  final List<CampusPostSummary> updates;

  const _LatestUpdatesList({required this.updates});

  @override
  Widget build(BuildContext context) {
    if (updates.isEmpty) {
      return const _SectionEmpty(
        icon: Icons.campaign_outlined,
        text: 'No campus announcements yet.',
      );
    }
    final visible = updates.take(_homeUpdateCount).toList();
    return Padding(
      padding: AppSpacing.pagePadding,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  indent: AppSpacing.md,
                  endIndent: AppSpacing.md,
                  color: AppColors.border,
                ),
              _UpdateRow(post: visible[i], lead: i == 0),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  final CampusPostSummary post;

  /// The newest item: bigger thumbnail, two-line title, and its summary.
  final bool lead;

  const _UpdateRow({required this.post, required this.lead});

  @override
  Widget build(BuildContext context) {
    final category = post.category ?? 'general';
    final (color, background, icon) = campusCategoryStyle('announcement', category);
    final categoryLabel = announcementCategoryLabels[category] ?? 'General';
    final summary = post.summary?.trim() ?? '';

    return InkWell(
      onTap: () => context.push('/home/posts/${post.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _UpdateThumb(
              coverUrl: post.coverUrl,
              icon: icon,
              color: color,
              background: background,
              size: lead ? 64 : 44,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    maxLines: lead ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleSmall.copyWith(
                      // Read titles step back; unread stay bold + dark so new ones stand out.
                      fontWeight: post.read ? FontWeight.w600 : FontWeight.w700,
                      color: post.read ? AppColors.textMid : AppColors.textDark,
                    ),
                  ),
                  if (lead && summary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMid,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  _UpdateMeta(
                    unread: !post.read,
                    text: '$categoryLabel · ${_postAge(post.publishAt)}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateMeta extends StatelessWidget {
  final bool unread;
  final String text;

  const _UpdateMeta({required this.unread, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (unread) ...[
          Semantics(
            label: 'Unread',
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// The post's cover photo, or its tinted category icon when it has none — never the generic
/// campus photo, which made every photo-less update look identical.
class _UpdateThumb extends StatelessWidget {
  final String? coverUrl;
  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  const _UpdateThumb({
    required this.coverUrl,
    required this.icon,
    required this.color,
    required this.background,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = AppIconTile(
      icon: icon,
      color: color,
      background: background,
      size: size,
    );
    if (coverUrl == null) return fallback;
    return ClipRRect(
      borderRadius: AppRadii.all(AppRadii.lg),
      child: CachedNetworkImage(
        key: const ValueKey('home-update-cover'),
        imageUrl: coverUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback,
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
