part of '../screens/group_detail_screen.dart';

/// One member row. The trailing menu only shows actions the viewer's role allows (the backend
/// re-checks): admins moderate members, only the owner can demote an admin or transfer ownership.
class _MemberTile extends StatelessWidget {
  final GroupMember member;
  final String? myRole;
  final bool busy;
  final void Function(String role) onChangeRole; // 'admin' | 'member'
  final VoidCallback onTransfer;
  final VoidCallback onRemove;
  final VoidCallback onBan;

  const _MemberTile({
    required this.member,
    required this.myRole,
    required this.busy,
    required this.onChangeRole,
    required this.onTransfer,
    required this.onRemove,
    required this.onBan,
  });

  String get _subtitle {
    if (member.isOwner) return 'Owner';
    if (member.isAdmin) return 'Admin';
    return member.major ?? 'Member';
  }

  List<_MemberAction> get _actions {
    final actions = <_MemberAction>[];
    final canModerateTarget = canModerate(myRole, member.role);
    if (canModerateTarget && member.role == 'member') {
      actions.add(_MemberAction('promote', 'Make admin', Icons.shield_outlined));
    }
    if (canModerateTarget && member.role == 'admin') {
      actions.add(_MemberAction('demote', 'Remove admin', Icons.remove_moderator_outlined));
    }
    if (myRole == 'owner' && !member.isOwner) {
      actions.add(_MemberAction('transfer', 'Transfer ownership', Icons.workspace_premium_outlined));
    }
    if (canModerateTarget) {
      actions.add(_MemberAction('remove', 'Remove', Icons.person_remove_outlined));
      actions.add(_MemberAction('ban', 'Ban', Icons.block, destructive: true));
    }
    return actions;
  }

  void _onSelected(String value) {
    switch (value) {
      case 'promote':
        onChangeRole('admin');
      case 'demote':
        onChangeRole('member');
      case 'transfer':
        onTransfer();
      case 'remove':
        onRemove();
      case 'ban':
        onBan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    // Tapping the row opens the member's profile (the ⋯ button absorbs its own taps).
    return InkWell(
      onTap: member.profileId != null
          ? () => context.push('/users/${member.profileId}', extra: member.displayName)
          : null,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      child: Row(
        children: [
          AvatarWidget(imageUrl: member.avatarUrl, size: 44, cacheScope: member.userId),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        member.nameOrFallback,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark),
                      ),
                    ),
                    if (member.isVerified) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: 13),
                    ],
                  ],
                ),
                Text(_subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          else if (actions.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted),
              onSelected: _onSelected,
              itemBuilder: (_) => [
                for (final a in actions)
                  PopupMenuItem(
                    value: a.value,
                    child: Row(
                      children: [
                        Icon(a.icon, size: 18, color: a.destructive ? AppColors.error : AppColors.textMid),
                        const SizedBox(width: 10),
                        Text(
                          a.label,
                          style: GoogleFonts.dmSans(color: a.destructive ? AppColors.error : AppColors.textDark),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      ),
    );
  }
}

class _MemberAction {
  final String value;
  final String label;
  final IconData icon;
  final bool destructive;
  const _MemberAction(this.value, this.label, this.icon, {this.destructive = false});
}
