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
            content: Text(e.toString()),
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

    return GestureDetector(
      onTap: () =>
          context.push('/activities/${a.id}', extra: widget.activity),
      child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image banner
          Stack(
            children: [
              SizedBox(
                height: 150,
                width: double.infinity,
                child: Image.asset(
                  'assets/images/school.png',
                  fit: BoxFit.cover,
                ),
              ),
              // Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withAlpha(20),
                        Colors.black.withAlpha(100),
                      ],
                    ),
                  ),
                ),
              ),
              // FEATURED badge
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'FEATURED',
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                if (a.description != null && a.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    a.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                // Date/time row
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      _formatDate(a.startTime),
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textMid),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.access_time_outlined,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      _formatTimeRange(a.startTime, a.endTime),
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textMid),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // Location row
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        a.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                            fontSize: 12, color: AppColors.textMid),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Going count + Join button
                Row(
                  children: [
                    const Icon(Icons.people_outline_rounded,
                        size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      '${a.participantCount} going',
                      style: GoogleFonts.dmSans(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    _JoinButton(
                      joined: joined,
                      loading: _loading,
                      onTap: _toggle,
                      full: a.maxParticipants != null &&
                          a.participantCount >= a.maxParticipants! &&
                          !joined,
                    ),
                  ],
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

// ── Compact card ──────────────────────────────────────────────────
