part of '../screens/campus_hub_screen.dart';

/// Up to two upcoming activities, so the section never crowds out announcements.
class _ActivitiesPreview extends ConsumerWidget {
  const _ActivitiesPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activitiesNotifierProvider);

    return async.cached(
      loading: () => const _PreviewLoading(),
      error: (_, _) => const _SectionEmpty(
        icon: Icons.event_busy_outlined,
        text: 'Could not load activities right now.',
      ),
      data: (activities) {
        if (activities.isEmpty) {
          return const _SectionEmpty(
            icon: Icons.event_available_outlined,
            text: 'No activities yet. Check back soon.',
          );
        }
        final visible = activities.take(2).toList();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == visible.length - 1 ? 0 : AppSpacing.sm,
                  ),
                  child: _ActivityPreviewCard(activity: visible[i]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityPreviewCard extends StatelessWidget {
  final Activity activity;
  const _ActivityPreviewCard({required this.activity});

  String get _going => activity.maxParticipants != null
      ? '${activity.participantCount}/${activity.maxParticipants} going'
      : '${activity.participantCount} going';

  @override
  Widget build(BuildContext context) {
    final start = activity.startTime.toLocal();

    return AppCard(
      onTap: () => context.push('/activities/${activity.id}', extra: activity),
      child: Row(
        children: [
          AppDateBlock(date: start, going: activity.hasJoined),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // The date block already says the day, so this line says *when* on it and
                // how full it is — it used to repeat the date and push the place off the end.
                _ActivityMetaRow(
                  icon: Icons.schedule_rounded,
                  text: '${AppDateFormat.weekdayTime(start)} · $_going',
                ),
                const SizedBox(height: 2),
                _ActivityMetaRow(
                  icon: Icons.place_outlined,
                  text: activity.location,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

class _ActivityMetaRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ActivityMetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMid),
          ),
        ),
      ],
    );
  }
}

/// Three student suggestions — tap a card to open the profile.
class _SuggestedConnectionsPreview extends ConsumerWidget {
  const _SuggestedConnectionsPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(discoveryNotifierProvider);

    return async.cached(
      loading: () => const _PreviewLoading(),
      error: (_, _) => const _SectionEmpty(
        icon: Icons.people_outline_rounded,
        text: 'Could not load suggested students right now.',
      ),
      data: (cards) {
        if (cards.isEmpty) {
          return const _SectionEmpty(
            icon: Icons.people_outline_rounded,
            text: 'No suggested connections yet.',
          );
        }
        final visible = cards.take(3).toList();
        // Three-across only while each card stays readable; below that, a strip of fixed-width
        // cards the student can swipe — same three suggestions, no squeeze.
        //
        // The test is the *card* width, not the row's. It used to be `maxWidth < 360`, but the
        // row is the screen minus two gutters, so a standard 393dp phone (353dp of row) got the
        // strip too — with the third card cut off at the edge, on most of the phones students
        // actually carry.
        // Do not use CrossAxisAlignment.stretch here — this Row lives inside a
        // ListView, which gives unbounded height and stretch would force infinite height.
        return Padding(
          padding: AppSpacing.pagePadding,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth =
                  (constraints.maxWidth - AppSpacing.md * 2) / 3;
              if (cardWidth < _minConnectionCardWidth) {
                return SizedBox(
                  height: _connectionStripHeight(context),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (_, i) => SizedBox(
                      width: 124,
                      child: _SuggestedConnectionCard(card: visible[i]),
                    ),
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < visible.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: i == visible.length - 1 ? 0 : AppSpacing.md,
                        ),
                        child: _SuggestedConnectionCard(card: visible[i]),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Under this a name like "Kwame Asante" ellipsizes to a fragment.
const _minConnectionCardWidth = 96.0;

/// The horizontal strip needs a fixed height; grow it with the text so large type is not clipped.
double _connectionStripHeight(BuildContext context) =>
    136 * MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.6);

/// A person, centred: avatar over name over major — how every directory and contact surface
/// presents someone, and it gives a narrow card a clear axis instead of a ragged left edge.
///
/// There used to be a small "add person" badge on the avatar. Tapping the card opens the profile;
/// it never sent a request, so the badge promised an action that was not there.
class _SuggestedConnectionCard extends StatelessWidget {
  final DiscoveryCard card;
  const _SuggestedConnectionCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () =>
          context.push('/users/${card.profileId}', extra: card.displayName),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarWidget(
            imageUrl: card.avatarUrl,
            size: 52,
            cacheScope: card.userId,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            card.displayName ?? 'LC Student',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            card.major ?? 'Student',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewLoading extends StatelessWidget {
  const _PreviewLoading();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [AppPreviewCardSkeleton(), AppPreviewCardSkeleton()],
    );
  }
}
