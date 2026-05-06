import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/activities_provider.dart';

// ── Filter definitions ───────────────────────────────────────────
const _filters = [
  ('all', 'All'),
  ('study', 'Study'),
  ('sports', 'Sports'),
  ('social', 'Social'),
  ('culture', 'Culture'),
];

// ── Screen ───────────────────────────────────────────────────────
class ActivitiesScreen extends ConsumerWidget {
  const ActivitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(activitiesFilterProvider);
    final async = ref.watch(activitiesNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/activities/create'),
        backgroundColor: AppColors.primary,
        elevation: 3,
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Header(),
            const SizedBox(height: 4),
            _FilterChips(
              selected: filter,
              onSelect: (f) =>
                  ref.read(activitiesFilterProvider.notifier).set(f),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(
                  onRetry: () =>
                      ref.invalidate(activitiesNotifierProvider),
                ),
                data: (activities) => activities.isEmpty
                    ? _EmptyState(
                        hasFilter: filter != 'all',
                        onClear: () => ref
                            .read(activitiesFilterProvider.notifier)
                            .set('all'),
                      )
                    : _ActivityList(activities: activities),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _LCBadge(),
              const SizedBox(width: 10),
              Text(
                'LC Connect',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              const Icon(Icons.notifications_outlined,
                  color: AppColors.textMuted, size: 24),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Activities',
            style: GoogleFonts.dmSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Find something happening on campus',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _LCBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        'LC',
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Filter chips ─────────────────────────────────────────────────
class _FilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _FilterChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          ..._filters.map((f) {
            final (code, label) = f;
            final on = selected == code;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onSelect(code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: on ? AppColors.primary : AppColors.border,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight:
                          on ? FontWeight.w600 : FontWeight.w400,
                      color: on ? Colors.white : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Activity list ─────────────────────────────────────────────────
class _ActivityList extends StatelessWidget {
  final List<Activity> activities;
  const _ActivityList({required this.activities});

  @override
  Widget build(BuildContext context) {
    final featured = activities.first;
    final rest = activities.skip(1).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      children: [
        _FeaturedCard(activity: featured),
        const SizedBox(height: 16),
        ...rest.map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CompactCard(activity: a),
            )),
      ],
    );
  }
}

// ── Featured card ─────────────────────────────────────────────────
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
    final isFull = a.maxParticipants != null &&
        a.participantCount >= a.maxParticipants! &&
        !joined;

    return GestureDetector(
      onTap: () =>
          context.push('/activities/${a.id}', extra: widget.activity),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60,
              height: 60,
              child: Image.asset(
                'assets/images/school.png',
                fit: BoxFit.cover,
              ),
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
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _formatDate(a.startTime),
                  style: GoogleFonts.dmSans(
                      fontSize: 11, color: AppColors.textMuted),
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
                        style: GoogleFonts.dmSans(
                            fontSize: 11, color: AppColors.textMuted),
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
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _CompactJoinButton(
                joined: joined,
                loading: _loading,
                full: isFull,
                onTap: _toggle,
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ── Join button (full-size for featured card) ─────────────────────
class _JoinButton extends StatelessWidget {
  final bool joined;
  final bool loading;
  final bool full;
  final VoidCallback onTap;
  const _JoinButton({
    required this.joined,
    required this.loading,
    required this.full,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = joined
        ? AppColors.textMuted
        : full
            ? AppColors.border
            : AppColors.primary;

    return SizedBox(
      height: 36,
      child: Material(
        color: joined ? AppColors.primarySoft : color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: full ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Center(
                    child: Text(
                      joined ? 'Joined' : full ? 'Full' : 'Join',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: joined ? AppColors.primary : Colors.white,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Compact join/leave button (circle icon) ───────────────────────
class _CompactJoinButton extends StatelessWidget {
  final bool joined;
  final bool loading;
  final bool full;
  final VoidCallback onTap;
  const _CompactJoinButton({
    required this.joined,
    required this.loading,
    required this.full,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: full ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: joined
              ? AppColors.primarySoft
              : full
                  ? AppColors.background
                  : AppColors.green,
          shape: BoxShape.circle,
          border: Border.all(
            color: joined
                ? AppColors.primary
                : full
                    ? AppColors.border
                    : AppColors.green,
            width: 1.5,
          ),
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(6),
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: AppColors.primary),
              )
            : Icon(
                joined ? Icons.check_rounded : Icons.add_rounded,
                size: 16,
                color: joined
                    ? AppColors.primary
                    : full
                        ? AppColors.textMuted
                        : Colors.white,
              ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool hasFilter;
  final VoidCallback onClear;
  const _EmptyState({required this.hasFilter, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined,
                size: 56, color: AppColors.border),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? 'No activities in this category'
                  : 'No upcoming activities',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilter
                  ? 'Try a different filter or check back soon'
                  : 'Be the first to create something!',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textMuted),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onClear,
                child: Text(
                  'Clear filter',
                  style: GoogleFonts.dmSans(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Couldn\'t load activities',
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: GoogleFonts.dmSans(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Date/time helpers ─────────────────────────────────────────────
String _formatDate(DateTime dt) => DateFormat('EEE, MMM d').format(dt);

String _formatTimeRange(DateTime start, DateTime? end) {
  final s = DateFormat('h:mm a').format(start);
  if (end == null) return s;
  return '$s – ${DateFormat('h:mm a').format(end)}';
}
