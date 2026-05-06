import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/activities_provider.dart';

class ActivityDetailScreen extends ConsumerStatefulWidget {
  final Activity activity;
  const ActivityDetailScreen({super.key, required this.activity});

  @override
  ConsumerState<ActivityDetailScreen> createState() =>
      _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  bool _loading = false;

  Future<void> _toggle(Activity activity) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final notifier = ref.read(activitiesNotifierProvider.notifier);
      if (activity.hasJoined) {
        await notifier.leave(activity.id);
      } else {
        await notifier.join(activity.id);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong. Please try again.',
              style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(activitiesNotifierProvider).asData?.value;
    final activity = list?.firstWhere(
          (a) => a.id == widget.activity.id,
          orElse: () => widget.activity,
        ) ??
        widget.activity;

    final isFull = activity.maxParticipants != null &&
        activity.participantCount >= activity.maxParticipants! &&
        !activity.hasJoined;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _JoinBar(
        activity: activity,
        isFull: isFull,
        loading: _loading,
        onToggle: () => _toggle(activity),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Collapsing banner ──────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textDark,
            title: Text(
              activity.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/school.png',
                    fit: BoxFit.cover,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withAlpha(20),
                          Colors.black.withAlpha(120),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 16,
                    child: _CategoryBadge(category: activity.category),
                  ),
                ],
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Title
                Text(
                  activity.title,
                  style: GoogleFonts.dmSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),

                // Participant count
                Row(
                  children: [
                    const Icon(Icons.people_outline_rounded,
                        size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      activity.maxParticipants != null
                          ? '${activity.participantCount} / ${activity.maxParticipants} going'
                          : '${activity.participantCount} going',
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.textMuted),
                    ),
                  ],
                ),

                // Description
                if (activity.description != null &&
                    activity.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    activity.description!,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: AppColors.textMid,
                      height: 1.6,
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                const Divider(color: AppColors.border),
                const SizedBox(height: 16),

                // Date & Time
                _DetailRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Date',
                  value: DateFormat('EEEE, MMMM d, y').format(activity.startTime),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.access_time_outlined,
                  label: 'Time',
                  value: _formatTimeRange(activity.startTime, activity.endTime),
                ),
                const SizedBox(height: 12),

                // Location
                _DetailRow(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  value: activity.location,
                ),

                // Capacity bar
                if (activity.maxParticipants != null) ...[
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 16),
                  _CapacityBar(activity: activity),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category badge ────────────────────────────────────────────────
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(220),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            category[0].toUpperCase() + category.substring(1),
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Detail row (icon + label + value) ────────────────────────────
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Capacity bar ──────────────────────────────────────────────────
class _CapacityBar extends StatelessWidget {
  final Activity activity;
  const _CapacityBar({required this.activity});

  @override
  Widget build(BuildContext context) {
    final max = activity.maxParticipants!;
    final count = activity.participantCount;
    final ratio = (count / max).clamp(0.0, 1.0);
    final spotsLeft = max - count;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Capacity',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            Text(
              spotsLeft > 0 ? '$spotsLeft spots left' : 'Full',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: spotsLeft > 0 ? AppColors.green : AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation<Color>(
              ratio >= 1.0 ? AppColors.error : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Join / Leave bottom bar ───────────────────────────────────────
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
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.of(context).viewPadding.bottom),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${activity.participantCount} going',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              if (activity.maxParticipants != null)
                Text(
                  '${activity.maxParticipants! - activity.participantCount} spots left',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, color: AppColors.textMuted),
                ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 44,
            width: 120,
            child: FilledButton(
              onPressed: isFull ? null : (loading ? null : onToggle),
              style: FilledButton.styleFrom(
                backgroundColor: activity.hasJoined
                    ? AppColors.primarySoft
                    : isFull
                        ? AppColors.border
                        : AppColors.primary,
                foregroundColor: activity.hasJoined
                    ? AppColors.primary
                    : Colors.white,
                minimumSize: const Size(0, 44),
              ),
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : Text(
                      activity.hasJoined
                          ? 'Leave'
                          : isFull
                              ? 'Full'
                              : 'Join',
                      style: GoogleFonts.dmSans(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────
String _formatTimeRange(DateTime start, DateTime? end) {
  final s = DateFormat('h:mm a').format(start);
  if (end == null) return s;
  return '$s – ${DateFormat('h:mm a').format(end)}';
}
