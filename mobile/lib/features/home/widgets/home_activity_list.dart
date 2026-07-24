part of '../screens/home_screen.dart';

class _ActivitiesList extends StatelessWidget {
  final List<Activity> activities;
  final bool loading;
  const _ActivitiesList({required this.activities, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading && activities.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: LinearProgressIndicator(
          backgroundColor: AppColors.border,
          color: AppColors.primary,
        ),
      );
    }
    if (activities.isEmpty) {
      return AppEmptyStateCard(
        icon: Icons.calendar_today_rounded,
        title: 'No upcoming activities',
        subtitle: 'Nothing scheduled right now.',
        actionLabel: 'Browse Activities',
        onAction: () => context.go('/activities'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: activities
            .map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _ActivityItem(
                    activity: a,
                    onTap: () => context.go(
                      '/activities/${a.id}',
                      extra: a,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final Activity activity;
  final VoidCallback onTap;
  const _ActivityItem({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('h:mm a').format(activity.startTime.toLocal());
    final emoji = _categoryEmoji(activity.category);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D111827),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 19)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    activity.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeLabel,
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.people_outline_rounded,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${activity.participantCount} going',
                      style: GoogleFonts.dmSans(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
