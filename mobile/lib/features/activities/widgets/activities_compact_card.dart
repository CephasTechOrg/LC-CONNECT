part of '../screens/activities_screen.dart';

class _CompactCard extends ConsumerStatefulWidget {
  final Activity activity;
  const _CompactCard({required this.activity});

  @override
  ConsumerState<_CompactCard> createState() => _CompactCardState();
}

class _CompactCardState extends ConsumerState<_CompactCard> {
  bool _loading = false;

  Future<void> _toggle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final notifier = ref.read(activitiesNotifierProvider.notifier);
      if (widget.activity.hasJoined) {
        await notifier.leave(widget.activity.id);
      } else {
        await notifier.join(widget.activity.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              apiErrorMessage(e, fallback: 'Could not update your RSVP — try again.'),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The 60×60 row thumbnail. A remote banner is cached and cropped to fill; while it loads, and
  /// if it fails, it falls back to the generic campus image rather than a blank or broken box.
  Widget _thumbnail(String? bannerUrl) {
    const fallback = Image(
      image: AssetImage('assets/images/school.webp'),
      fit: BoxFit.cover,
    );
    if (bannerUrl == null || bannerUrl.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: bannerUrl,
      fit: BoxFit.cover,
      placeholder: (_, _) => const ColoredBox(color: AppColors.primaryPale),
      errorWidget: (_, _, _) => fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final joined = a.hasJoined;
    final isFull = a.maxParticipants != null &&
        a.participantCount >= a.maxParticipants! &&
        !joined;

    // The layout is unchanged; only the surface matches Home now (borderless, soft shadow, and a
    // ripple on tap, which the bare GestureDetector did not give).
    return AppCard(
      onTap: () =>
          context.push('/activities/${a.id}', extra: widget.activity),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          // Thumbnail: the activity's own banner when it has one, cropped square; otherwise the
          // generic campus image. Previously every row showed `school.webp`, so a list of
          // activities with distinct banners looked identical down the page.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: _thumbnail(a.bannerUrl),
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppDateFormat.date(a.startTime),
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 11, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        a.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w400,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Count + toggle button
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_outline_rounded,
                      size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text(
                    '${a.participantCount}',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              _CompactJoinButton(
                joined: joined,
                loading: _loading,
                full: isFull,
                onTap: _toggle,
                title: a.title,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Join button (full-size for featured card) ─────────────────────
