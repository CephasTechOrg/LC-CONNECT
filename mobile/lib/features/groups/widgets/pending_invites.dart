import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../messages/providers/messages_provider.dart';
import '../data/group_models.dart';
import '../providers/groups_provider.dart';

/// The invitee's side of the invite flow: groups you've been invited to (including
/// private/unlisted ones that never appear in discovery), with Accept / Decline.
/// Renders nothing when you have no pending invites.
class PendingInvitesSection extends ConsumerStatefulWidget {
  const PendingInvitesSection({super.key});

  @override
  ConsumerState<PendingInvitesSection> createState() => _PendingInvitesSectionState();
}

class _PendingInvitesSectionState extends ConsumerState<PendingInvitesSection> {
  final _busy = <String>{}; // group ids with an accept/decline in flight

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.dmSans(color: Colors.white)),
        backgroundColor: error ? AppColors.error : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _act(GroupSummary group, {required bool accept}) async {
    if (_busy.contains(group.id)) return;
    setState(() => _busy.add(group.id));
    try {
      final repo = ref.read(groupsRepositoryProvider);
      accept ? await repo.acceptInvite(group.id) : await repo.declineInvite(group.id);
      if (!mounted) return;
      ref.invalidate(myInvitesProvider);
      if (accept) {
        // Now a member: surface it in discovery state, My Groups, and the Messages inbox.
        ref.invalidate(discoverGroupsProvider);
        ref.invalidate(myGroupsProvider);
        ref.invalidate(threadsNotifierProvider);
      }
      _snack(accept ? 'Joined ${group.name}' : 'Invite declined');
    } catch (_) {
      _snack('Could not ${accept ? 'accept' : 'decline'} — try again', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(group.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(myInvitesProvider).asData?.value ?? const <GroupSummary>[];
    if (invites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            'Pending invites',
            style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
        ),
        for (final g in invites)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 9),
            child: _InviteCard(
              group: g,
              busy: _busy.contains(g.id),
              onAccept: () => _act(g, accept: true),
              onDecline: () => _act(g, accept: false),
            ),
          ),
      ],
    );
  }
}

class _InviteCard extends StatelessWidget {
  final GroupSummary group;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _InviteCard({required this.group, required this.busy, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            child: group.avatarUrl != null
                ? Image.network(group.avatarUrl!, fit: BoxFit.cover, width: 40, height: 40,
                    errorBuilder: (_, _, _) => const Icon(Icons.groups_outlined, size: 18, color: AppColors.primary))
                : const Icon(Icons.groups_outlined, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDark),
                ),
                Text(
                  'Invited you to join',
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            _InviteBtn(label: 'Decline', filled: false, onTap: onDecline),
            const SizedBox(width: 6),
            _InviteBtn(label: 'Accept', filled: true, onTap: onAccept),
          ],
        ],
      ),
    );
  }
}

class _InviteBtn extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _InviteBtn({required this.label, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: filled ? AppColors.primary : AppColors.border, width: 1.5),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : AppColors.textMid,
            ),
          ),
        ),
      ),
    );
  }
}
