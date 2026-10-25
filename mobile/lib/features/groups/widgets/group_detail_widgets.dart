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
              AvatarWidget(
                imageUrl: group.avatarUrl,
                size: 88,
                cacheScope: group.id,
                previewHeroTag: 'group-avatar:${group.id}',
                previewName: group.name,
              ),
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
      error: (_, _) => AppInlineMessage(message: "Couldn't load this", onRetry: onRetry),
      data: (members) {
        final sorted = [...members]..sort((a, b) => roleRank(b.role).compareTo(roleRank(a.role)));
        // One card, rows split by hairlines — the members used to float on the page background
        // while the mute switch above them sat in a box.
        return _GroupSection(
          title: 'Members · ${members.length}',
          children: [
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

/// A titled group of rows in one card, hairlines between them — members, requests, and the
/// leave/report actions all share it, so the page reads as a few clear blocks.
class _GroupSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const _GroupSection({this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
              child: Text(
                title!,
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: AppSpacing.md,
                      endIndent: AppSpacing.md,
                      color: AppColors.border,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Red that passes AA on white (the brand error red is 3.5:1) — kept for the actions that remove
/// you or the group.
const _dangerRed = Color(0xFFB91C1C);

// ── Footer (leave / delete) ──────────────────────────────────────────────────

class _FooterActions extends StatelessWidget {
  final GroupRead group;
  final VoidCallback onReport;
  final VoidCallback onLeave;
  final VoidCallback onDelete;
  const _FooterActions({
    required this.group,
    required this.onReport,
    required this.onLeave,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Quiet rows in one card, not a stack of red-outlined boxes: each opens a confirmation, and
    // that dialog is where the action turns red and solid (DESIGN_PRINCIPLES rule 7).
    return _GroupSection(
      children: [
        // The owner manages the group rather than reporting it.
        if (!group.iAmOwner)
          _DangerRow(icon: Icons.flag_outlined, label: 'Report group', onTap: onReport),
        if (!group.iAmOwner && group.isMember)
          _DangerRow(icon: Icons.logout_rounded, label: 'Leave group', onTap: onLeave),
        if (group.iAmOwner)
          _DangerRow(icon: Icons.delete_outline_rounded, label: 'Delete group', onTap: onDelete),
      ],
    );
  }
}

/// Personal "mute notifications" toggle for a member — suppresses push, messages still arrive live.
class _MuteRow extends StatelessWidget {
  final bool muted;
  final ValueChanged<bool> onChanged;
  const _MuteRow({required this.muted, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
      child: Row(
        children: [
          Icon(muted ? Icons.notifications_off_outlined : Icons.notifications_outlined,
              size: 20, color: AppColors.textMid),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Mute notifications',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textDark)),
          ),
          Switch(
            value: muted,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: _dangerRed),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: _dangerRed),
            ),
          ],
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
      borderRadius: AppRadii.all(AppRadii.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.all(AppRadii.full),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppColors.primaryText),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryText,
                ),
              ),
            ],
          ),
        ),
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
