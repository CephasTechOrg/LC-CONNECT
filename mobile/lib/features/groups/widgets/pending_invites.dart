import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../messages/providers/messages_provider.dart';
import '../data/group_models.dart';
import '../providers/groups_provider.dart';

/// The invitee's side of the invite flow: groups you've been invited to (including
/// private/unlisted ones that never appear in discovery), with Accept / Decline.
/// Renders nothing when you have no pending invites.
///
/// On the Groups page it stays small: one invite shows as its own card, several collapse into a
/// single "3 group invites" row that opens the full list in a sheet ([inSheet]). A stack of
/// invite cards used to push everything else off the first screen.
class PendingInvitesSection extends ConsumerStatefulWidget {
  const PendingInvitesSection({super.key, this.inSheet = false});

  final bool inSheet;

  @override
  ConsumerState<PendingInvitesSection> createState() => _PendingInvitesSectionState();
}

class _PendingInvitesSectionState extends ConsumerState<PendingInvitesSection> {
  final _busy = <String>{}; // group ids with an accept/decline in flight

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
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
    // `.value`, not `asData?.value`: during a refresh the state is AsyncLoading *carrying* the
    // previous value, so `asData` is null and the section used to vanish and reappear.
    final invites = ref.watch(myInvitesProvider).value ?? const <GroupSummary>[];
    if (invites.isEmpty) {
      return widget.inSheet
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No pending invites', style: AppTypography.body.copyWith(color: AppColors.textMuted)),
            )
          : const SizedBox.shrink();
    }
    if (!widget.inSheet && invites.length > 1) {
      return _InvitesSummaryRow(invites: invites, onTap: _openSheet);
    }
    if (!widget.inSheet) {
      final g = invites.single;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: _InviteCard(
          group: g,
          busy: _busy.contains(g.id),
          onAccept: () => _act(g, accept: true),
          onDecline: () => _act(g, accept: false),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            'Pending invites',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
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

extension on _PendingInvitesSectionState {
  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 12),
          child: PendingInvitesSection(inSheet: true),
        ),
      ),
    );
  }
}

/// "3 group invites" — one tinted row in place of three cards.
class _InvitesSummaryRow extends StatelessWidget {
  final List<GroupSummary> invites;
  final VoidCallback onTap;
  const _InvitesSummaryRow({required this.invites, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final names = invites.map((g) => g.name).take(2).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Material(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.mail_outline_rounded, size: 20, color: AppColors.primaryText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${invites.length} group invites',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        invites.length > 2 ? '$names and more' : names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: AppColors.textMid),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
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
      // Soft blue, no outline: an invite is waiting on you, so it is the one tinted card here.
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
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
                ? CachedNetworkImage(
                    imageUrl: group.avatarUrl!,
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    errorWidget: (_, _, _) =>
                        const Icon(Icons.groups_outlined, size: 18, color: AppColors.primary))
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
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Invited you to join',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.textMuted,
                  ),
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

/// Accept is the action (blue fill); Decline steps back to a flat grey pill — the same two
/// treatments as every join control in the app, on a 48dp target.
class _InviteBtn extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _InviteBtn({required this.label, required this.filled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: filled ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: filled ? Colors.white : AppColors.textMid,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
