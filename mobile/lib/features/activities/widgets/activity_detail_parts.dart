part of '../screens/activity_detail_screen.dart';

class _DetailBanner extends StatelessWidget {
  final Activity activity;
  const _DetailBanner({required this.activity});

  @override
  Widget build(BuildContext context) {
    const fallback = 'assets/images/school.webp';
    return Stack(
      fit: StackFit.expand,
      children: [
        if (activity.bannerUrl != null)
          CachedNetworkImage(
            imageUrl: activity.bannerUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => Image.asset(fallback, fit: BoxFit.cover),
          )
        else
          Image.asset(fallback, fit: BoxFit.cover),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withAlpha(20), Colors.black.withAlpha(120)],
            ),
          ),
        ),
        Positioned(
          bottom: AppSpacing.md,
          left: AppSpacing.gutter,
          child: _CategoryBadge(category: activity.category),
        ),
      ],
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  final String category;
  const _CategoryBadge({required this.category});

  IconData get _icon => switch (category) {
        'study' => Icons.menu_book_outlined,
        'sports' => Icons.sports_outlined,
        'social' => Icons.people_outline,
        'culture' => Icons.palette_outlined,
        _ => Icons.star_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: AppRadii.all(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 14, color: AppColors.primaryText),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            category[0].toUpperCase() + category.substring(1),
            style: AppTypography.label.copyWith(color: AppColors.primaryText),
          ),
        ],
      ),
    );
  }
}

/// "6 / 10 going ›" — opens the roster.
class _GoingLink extends StatelessWidget {
  final Activity activity;
  final VoidCallback onTap;
  const _GoingLink({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final max = activity.maxParticipants;
    final label = max != null
        ? '${activity.participantCount} / $max going'
        : '${activity.participantCount} going';
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline_rounded, size: 16, color: AppColors.primaryText),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primaryText),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIconTile(icon: icon),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The activity's summary panel: when, and how full, beside Join — the facts that decide whether
/// to join, next to the button that does it.
class _ActivitySummary extends StatelessWidget {
  final Activity activity;
  final bool isFull;
  final bool loading;
  final VoidCallback onToggle;

  const _ActivitySummary({
    required this.activity,
    required this.isFull,
    required this.loading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final max = activity.maxParticipants;
    final joined = activity.hasJoined;
    final spotsLeft = max == null ? null : max - activity.participantCount;

    final AppSummaryFact who = switch (spotsLeft) {
      null => AppSummaryFact(
          icon: Icons.people_outline_rounded,
          label: 'Going',
          value: '${activity.participantCount}',
        ),
      <= 0 => const AppSummaryFact(icon: Icons.people_outline_rounded, label: 'Spots', value: 'Full'),
      _ => AppSummaryFact(
          icon: Icons.people_outline_rounded,
          label: 'Spots',
          value: '$spotsLeft left',
        ),
    };

    return AppSummaryPanel(
      facts: [
        AppSummaryFact(
          icon: Icons.calendar_today_outlined,
          label: 'Date',
          value: AppDateFormat.date(activity.startTime),
        ),
        AppSummaryFact(
          icon: Icons.schedule_rounded,
          label: 'Time',
          value: AppDateFormat.compactTimeRange(activity.startTime, activity.endTime),
        ),
        who,
      ],
      progress: max == null ? null : activity.participantCount / max,
      // Once joined the panel says so, and Leave steps down to an outline beside it.
      status: joined
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    "You're going",
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            )
          : null,
      action: AppSummaryAction(
        label: joined ? 'Leave' : (isFull ? 'Full' : 'Join'),
        outlined: joined,
        loading: loading,
        onPressed: isFull ? null : onToggle,
      ),
    );
  }
}
