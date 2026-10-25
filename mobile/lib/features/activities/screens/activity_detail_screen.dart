import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_summary_panel.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/util/app_date_format.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/activities_provider.dart';
import '../widgets/activity_participants_sheet.dart';
import 'create_activity_screen.dart';

part '../widgets/activity_detail_parts.dart';

const _bannerHeight = 200.0;

class ActivityDetailScreen extends ConsumerStatefulWidget {
  final Activity activity;
  const ActivityDetailScreen({super.key, required this.activity});

  @override
  ConsumerState<ActivityDetailScreen> createState() =>
      _ActivityDetailScreenState();
}

class _ActivityDetailScreenState extends ConsumerState<ActivityDetailScreen> {
  bool _loading = false;

  /// The title lives in the content below the banner. It used to also sit in the app bar over the
  /// banner, so the screen opened with the same title twice; now the bar only shows it once the
  /// banner has scrolled away and the big title has gone with it.
  final _scroll = ScrollController();
  bool _titleInBar = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > _bannerHeight - kToolbarHeight;
      if (show != _titleInBar) setState(() => _titleInBar = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _edit(Activity activity) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CreateActivityScreen(existing: activity)),
    );
  }

  Future<void> _cancel(Activity activity) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel activity?', style: GoogleFonts.dmSans(fontWeight: FontWeight.w700)),
        content: Text('This removes "${activity.title}" for everyone. This cannot be undone.',
            style: GoogleFonts.dmSans(color: AppColors.textMid)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text('Keep', style: GoogleFonts.dmSans(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: Text('Cancel activity',
                  style: GoogleFonts.dmSans(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(activitiesNotifierProvider.notifier).cancel(activity.id);
      if (mounted) Navigator.of(context).pop(); // back to the list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(apiErrorMessage(e, fallback: 'Could not cancel — try again'), style: GoogleFonts.dmSans()),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            apiErrorMessage(e, fallback: 'Could not update your RSVP — try again.'),
            style: GoogleFonts.dmSans(),
          ),
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

    final myId = ref.watch(authNotifierProvider).asData?.value?.id;
    final isCreator = myId != null && myId == activity.creatorId;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: _ActivitySummary(
        activity: activity,
        isFull: isFull,
        loading: _loading,
        onToggle: () => _toggle(activity),
      ),
      body: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverAppBar(
            expandedHeight: _bannerHeight,
            pinned: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textDark,
            title: AnimatedOpacity(
              opacity: _titleInBar ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text(
                activity.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
            actions: [
              if (isCreator)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) => v == 'edit' ? _edit(activity) : _cancel(activity),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit activity')),
                    const PopupMenuItem(value: 'cancel', child: Text('Cancel activity')),
                  ],
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _DetailBanner(activity: activity),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xl,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  activity.title,
                  style: AppTypography.display.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                // The one place the count appears — tap to see who's going (public roster).
                _GoingLink(
                  activity: activity,
                  onTap: () => showActivityParticipantsSheet(context, activity.id),
                ),
                if (activity.description != null &&
                    activity.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    activity.description!.trim(),
                    style: AppTypography.body.copyWith(color: AppColors.textMid, height: 1.6),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                // Where — the one fact too long for a panel column. When, and how full, are in
                // the summary panel below, beside the action they decide.
                _DetailRow(
                  icon: Icons.place_outlined,
                  label: 'Location',
                  value: activity.location,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
