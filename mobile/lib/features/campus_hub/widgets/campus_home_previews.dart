part of '../screens/campus_hub_screen.dart';

const _cardShadow = BoxShadow(
  color: Color(0x0A111827),
  blurRadius: 3,
  offset: Offset(0, 1),
);

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
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == visible.length - 1 ? 0 : 11),
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
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('/activities/${activity.id}', extra: activity),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [_cardShadow],
          ),
          child: Row(
            children: [
              _ActivityDateBlock(date: start),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _ActivityMetaRow(
                      icon: Icons.place_outlined,
                      text: '${DateFormat('EEE, MMM d').format(start)} · ${activity.location}',
                    ),
                    const SizedBox(height: 3),
                    _ActivityMetaRow(icon: Icons.people_outline_rounded, text: _going),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.calendar_today_outlined,
                  size: 15,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
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
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 0.63,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('d').format(date),
            style: GoogleFonts.dmSans(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
              height: 1,
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
            style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMid),
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
        // Do not use CrossAxisAlignment.stretch here — this Row lives inside a
        // ListView, which gives unbounded height and stretch would force infinite height.
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < visible.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == visible.length - 1 ? 0 : 12),
                    child: _SuggestedConnectionCard(card: visible[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SuggestedConnectionCard extends StatelessWidget {
  final DiscoveryCard card;
  const _SuggestedConnectionCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('/users/${card.profileId}', extra: card.displayName),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [_cardShadow],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ConnectionAvatar(card: card),
              const SizedBox(height: 9),
              Text(
                card.displayName ?? 'LC Student',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                card.major ?? 'Student',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
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
      width: 48,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AvatarWidget(imageUrl: card.avatarUrl, size: 48, cacheScope: card.userId),
          Positioned(
            bottom: -3,
            left: -3,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                size: 13,
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}
