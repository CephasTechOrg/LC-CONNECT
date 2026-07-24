part of '../screens/group_detail_screen.dart';

// ── Header ──────────────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  final GroupRead group;
  final bool uploading;
  final VoidCallback? onEditAvatar;
  const _GroupHeader({required this.group, required this.uploading, this.onEditAvatar});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Stack(
            children: [
              AvatarWidget(imageUrl: group.avatarUrl, size: 88, cacheScope: group.id),
              if (uploading)
                const Positioned.fill(
                  child: CircleAvatar(
                    backgroundColor: Colors.black26,
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  ),
                ),
              if (onEditAvatar != null && !uploading)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: onEditAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_rounded, size: 15, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            group.name,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            '${_categoryLabel(group.category)} · ${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
          ),
          if (group.description != null && group.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              group.description!,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textMid, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Members list (loads its own provider) ────────────────────────────────────

class _MembersList extends ConsumerWidget {
  final String groupId;
  final String? myRole;
  final Set<String> busy;
  final void Function(GroupMember, String role) onChangeRole;
  final void Function(GroupMember) onTransfer;
  final void Function(GroupMember) onRemove;
  final void Function(GroupMember) onBan;
  final VoidCallback onRetry;

  const _MembersList({
    required this.groupId,
    required this.myRole,
    required this.busy,
    required this.onChangeRole,
    required this.onTransfer,
    required this.onRemove,
    required this.onBan,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupMembersProvider(groupId));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (_, _) => _ErrorRetry(onRetry: onRetry),
      data: (members) {
        final sorted = [...members]..sort((a, b) => roleRank(b.role).compareTo(roleRank(a.role)));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Members (${members.length})',
                style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
              ),
            ),
            for (final m in sorted)
              _MemberTile(
                member: m,
                myRole: myRole,
                busy: busy.contains(m.userId),
                onChangeRole: (role) => onChangeRole(m, role),
                onTransfer: () => onTransfer(m),
                onRemove: () => onRemove(m),
                onBan: () => onBan(m),
              ),
          ],
        );
      },
    );
  }
}

// ── Footer (leave / delete) ──────────────────────────────────────────────────

class _FooterActions extends StatelessWidget {
  final GroupRead group;
  final VoidCallback onLeave;
  final VoidCallback onDelete;
  const _FooterActions({required this.group, required this.onLeave, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (!group.iAmOwner && group.isMember)
            _DangerRow(icon: Icons.logout_rounded, label: 'Leave group', onTap: onLeave),
          if (group.iAmOwner)
            _DangerRow(icon: Icons.delete_outline_rounded, label: 'Delete group', onTap: onDelete),
        ],
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DangerRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.error),
              const SizedBox(width: 12),
              Text(label, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(label, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text("Couldn't load this", style: GoogleFonts.dmSans(color: AppColors.textMuted)),
          TextButton(
            onPressed: onRetry,
            child: Text('Retry', style: GoogleFonts.dmSans(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

String _categoryLabel(String category) => switch (category) {
      'club' => 'Clubs & Sports',
      'class' => 'Academic',
      'housing' => 'Housing',
      _ => 'Interest',
    };
