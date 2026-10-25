part of '../screens/activities_screen.dart';

class _FeaturedCard extends ConsumerStatefulWidget {
  final Activity activity;
  const _FeaturedCard({required this.activity});

  @override
  ConsumerState<_FeaturedCard> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends ConsumerState<_FeaturedCard> {
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

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    final joined = a.hasJoined;
    final hasBanner = a.bannerUrl != null;

    return GestureDetector(
      onTap: () => context.push('/activities/${a.id}', extra: widget.activity),
      child: Container(
        // Borderless on a soft shadow — the same surface as the cards on Home.
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.sheet),
          boxShadow: AppShadows.soft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasBanner)
                    CachedNetworkImage(
                      imageUrl: a.bannerUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const ColoredBox(color: AppColors.primaryPale),
                    )
                  else ...[
                    const ColoredBox(color: AppColors.primaryPale),
                    Positioned(
                      right: -20,
                      top: 0,
                      bottom: 0,
                      child: Opacity(
                        opacity: 0.55,
                        child: Image.asset('assets/images/school.webp', fit: BoxFit.contain),
                      ),
                    ),
                  ],
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: hasBanner ? Alignment.topCenter : Alignment.centerLeft,
                        end: hasBanner ? Alignment.bottomCenter : Alignment.centerRight,
                        colors: hasBanner
                            ? [Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.6)]
                            : [
                                AppColors.primaryPale.withValues(alpha: 0.98),
                                AppColors.primaryPale.withValues(alpha: 0.05),
                              ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 13,
                    left: 15,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        // Sentence case, not capitals — DESIGN_PRINCIPLES rule 2.
                        'Featured',
                        // 10, not 9: the smallest size on the app's type scale.
                        style: AppTypography.micro.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 15,
                    bottom: 13,
                    right: 100,
                    child: Text(
                      a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title.copyWith(
                        fontWeight: FontWeight.w700,
                        color: hasBanner ? Colors.white : AppColors.textDark,
                        height: 1.25,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 15,
                    // The button's 48dp target extends 6dp above and below the visible pill.
                    bottom: 8,
                    child: _JoinButton(
                      joined: joined,
                      loading: _loading,
                      onTap: _toggle,
                      full: a.maxParticipants != null &&
                          a.participantCount >= a.maxParticipants! &&
                          !joined,
                      title: a.title,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a.description != null && a.description!.isNotEmpty) ...[
                    Text(
                      a.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _MetaRow(
                    icon: Icons.calendar_today_outlined,
                    text: AppDateFormat.date(a.startTime),
                  ),
                  _MetaRow(
                    icon: Icons.access_time_outlined,
                    text: AppDateFormat.timeRange(a.startTime, a.endTime),
                  ),
                  _MetaRow(
                    icon: Icons.location_on_outlined,
                    text: a.location,
                  ),
                  _MetaRow(
                    icon: Icons.people_outline_rounded,
                    text: '${a.participantCount} going',
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

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
