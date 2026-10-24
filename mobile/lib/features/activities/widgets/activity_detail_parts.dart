part of '../screens/activity_detail_screen.dart';

/// Darker than [AppColors.error]: the brand red is 3.5:1 on the page, under AA for 13px text.
const _fullRed = Color(0xFFB91C1C);

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

/// When, where and how full — grouped in one card instead of rows split by divider lines.
class _DetailsCard extends StatelessWidget {
  final Activity activity;
  const _DetailsCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppSpacing.cardPadding,
      child: Column(
        children: [
          _DetailRow(
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: AppDateFormat.fullDate(activity.startTime),
          ),
          const SizedBox(height: AppSpacing.md),
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Time',
            value: AppDateFormat.timeRange(activity.startTime, activity.endTime),
          ),
          const SizedBox(height: AppSpacing.md),
          _DetailRow(
            icon: Icons.place_outlined,
            label: 'Location',
            value: activity.location,
          ),
          if (activity.maxParticipants != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _CapacityBar(activity: activity),
          ],
        ],
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

class _CapacityBar extends StatelessWidget {
  final Activity activity;
  const _CapacityBar({required this.activity});

  @override
  Widget build(BuildContext context) {
    final max = activity.maxParticipants!;
    final ratio = (activity.participantCount / max).clamp(0.0, 1.0);
    final spotsLeft = max - activity.participantCount;
    final full = spotsLeft <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Capacity',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            // Brand blue, not green: green was 2.35:1 and a second accent colour.
            Text(
              full ? 'Full' : '$spotsLeft spots left',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: full ? _fullRed : AppColors.primaryText,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadii.all(AppRadii.full),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.primarySoft,
            valueColor: AlwaysStoppedAnimation<Color>(full ? _fullRed : AppColors.primary),
          ),
        ),
      ],
    );
  }
}

/// The action, pinned: one full-width button, thumb-reachable, on a white bar that lifts off the
/// page with a soft shadow instead of a hairline.
///
/// It used to repeat the count ("6 going · 4 spots left") beside a small button — the third time
/// the screen stated it. Now the bar carries only the action and, once joined, that you are going.
class _JoinBar extends StatelessWidget {
  final Activity activity;
  final bool isFull;
  final bool loading;
  final VoidCallback onToggle;

  const _JoinBar({
    required this.activity,
    required this.isFull,
    required this.loading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final joined = activity.hasJoined;
    final (background, foreground, label) = joined
        ? (AppColors.primarySoft, AppColors.primaryText, 'Leave')
        : isFull
            ? (const Color(0xFFEEF2F6), AppColors.textMuted, 'Full')
            : (AppColors.primary, Colors.white, 'Join');

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [BoxShadow(color: Color(0x0F1B3A5C), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.md + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (joined) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.primaryText),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Text(
                    "You're going",
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: isFull || loading ? null : onToggle,
                style: FilledButton.styleFrom(
                  backgroundColor: background,
                  foregroundColor: foreground,
                  disabledBackgroundColor: background,
                  disabledForegroundColor: foreground,
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.all(AppRadii.full)),
                ),
                child: loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                      )
                    : Text(
                        label,
                        style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
