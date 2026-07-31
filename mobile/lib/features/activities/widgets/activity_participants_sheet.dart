import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../providers/activities_provider.dart';

/// Bottom sheet showing an activity's roster — names + avatars, organizer first, tappable to
/// each person's profile. Public list; no moderation.
Future<void> showActivityParticipantsSheet(BuildContext context, String activityId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ParticipantsSheet(activityId: activityId),
  );
}

class _ParticipantsSheet extends ConsumerWidget {
  final String activityId;
  const _ParticipantsSheet({required this.activityId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activityParticipantsProvider(activityId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Text('Going', style: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                const SizedBox(width: 6),
                async.maybeWhen(
                  data: (p) => Text('· ${p.length}', style: GoogleFonts.dmSans(fontSize: 15, color: AppColors.textMuted)),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Text("Couldn't load the list", style: GoogleFonts.dmSans(color: AppColors.textMuted)),
              ),
              data: (people) => people.isEmpty
                  ? Center(child: Text('No one yet', style: GoogleFonts.dmSans(color: AppColors.textMuted)))
                  : ListView.builder(
                      controller: controller,
                      itemCount: people.length,
                      itemBuilder: (_, i) => _ParticipantTile(participant: people[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final ActivityParticipant participant;
  const _ParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    final pid = participant.profileId;
    return ListTile(
      onTap: pid != null ? () => context.push('/users/$pid', extra: participant.displayName) : null,
      leading: AvatarWidget(imageUrl: participant.avatarUrl, size: 42, cacheScope: participant.userId),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(participant.name,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark)),
          ),
          if (participant.isVerified) ...[
            const SizedBox(width: 4),
            const VerifiedBadge(size: 13),
          ],
        ],
      ),
      trailing: participant.isCreator
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
              child: Text('Organizer',
                  style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
            )
          : (pid != null ? const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted) : null),
    );
  }
}
