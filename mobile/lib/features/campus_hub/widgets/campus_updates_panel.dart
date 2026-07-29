part of '../screens/campus_hub_screen.dart';

/// Announcements panel — the most recent campus update, kept high on the page so
/// it is never pushed below the fold by the rest of the dashboard.
class _LatestUpdatesPanel extends StatelessWidget {
  final List<CampusPostSummary> updates;

  const _LatestUpdatesPanel({required this.updates});

  @override
  Widget build(BuildContext context) {
    final featured = updates.isEmpty ? null : updates.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF264A6E), Color(0xFF1B3A5C)],
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x471B3A5C), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_outlined, color: Colors.white, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Latest updates',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const _UpdatesSeeAll(),
              ],
            ),
            const SizedBox(height: 13),
            if (featured == null)
              Text(
                'No campus announcements yet.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              )
            else
              _FeaturedUpdateCard(post: featured),
          ],
        ),
      ),
    );
  }
}

class _UpdatesSeeAll extends ConsumerWidget {
  const _UpdatesSeeAll();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live count of new announcements since the user last opened the list — ticks up in real time.
    final count = ref.watch(announcementCountProvider);
    return GestureDetector(
      onTap: () => context.push('/home/updates'),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Text(
            'See all',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 7),
            Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ),
          ],
        ],
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
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: () => context.push('/home/posts/${post.id}'),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  campusSpotlightBackground,
                  width: 58,
                  height: 58,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
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
                        style: GoogleFonts.dmSans(
                          fontSize: 12.5,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _postAge(post.publishAt),
                      style: GoogleFonts.dmSans(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.6),
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
