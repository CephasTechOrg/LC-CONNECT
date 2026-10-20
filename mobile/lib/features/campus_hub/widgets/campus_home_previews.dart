part of '../screens/campus_hub_screen.dart';

/// Up to two upcoming activities, so the section never crowds out announcements.
class _ActivitiesPreview extends ConsumerWidget {
  const _ActivitiesPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activitiesNotifierProvider);

    return async.when(
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

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: () =>
            context.push('/activities/${activity.id}', extra: activity),
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _ActivityDateBlock(date: start),
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
                    const SizedBox(height: 4),
                    _ActivityMetaRow(
                      icon: Icons.place_outlined,
                      text:
                          '${DateFormat('EEE, MMM d').format(start)} · ${activity.location}',
                    ),
                    const SizedBox(height: 3),
                    _ActivityMetaRow(
                      icon: Icons.people_outline_rounded,
                      text: _going,
                    ),
                  ],
                ),
              ),
              // No trailing calendar box: the date block on the left already
              // says it, and on a 320dp phone that box cost ~46dp of title width.
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityDateBlock extends StatelessWidget {
  final DateTime date;
  const _ActivityDateBlock({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: AppTypography.micro.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('d').format(date),
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
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
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 5),
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

    return async.when(
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
        // Three-across only works while each card stays readable. Below ~360dp
        // a card is under 95dp wide and names/majors ellipsize to fragments, so
        // switch to a horizontal strip of fixed-width cards the student can
        // swipe — same three suggestions, no squeeze.
        // Do not use CrossAxisAlignment.stretch here — this Row lives inside a
        // ListView, which gives unbounded height and stretch would force infinite height.
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.xs,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 360) {
                return SizedBox(
                  height: 138,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (_, i) => SizedBox(
                      width: 132,
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

/// Compact preview aligned with Connect discovery density (radius 14, avatar 52, no shadow).
class _SuggestedConnectionCard extends StatelessWidget {
  final DiscoveryCard card;
  const _SuggestedConnectionCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: InkWell(
        onTap: () =>
            context.push('/users/${card.profileId}', extra: card.displayName),
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConnectionAvatar(card: card),
              const SizedBox(height: AppSpacing.sm),
              Text(
                card.displayName ?? 'LC Student',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionAvatar extends StatelessWidget {
  final DiscoveryCard card;
  const _ConnectionAvatar({required this.card});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AvatarWidget(
            imageUrl: card.avatarUrl,
            size: 52,
            cacheScope: card.userId,
          ),
          Positioned(
            bottom: -2,
            left: -2,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                size: 12,
                color: AppColors.primary,
              ),
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
