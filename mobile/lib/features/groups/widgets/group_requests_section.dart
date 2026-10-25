part of '../screens/group_detail_screen.dart';

/// Pending join requests, shown to admins/owner only. Renders nothing when there are none
/// (or on the 403 a non-admin would get). Approving/rejecting refreshes the members list.
class _RequestsSection extends ConsumerWidget {
  final String groupId;
  final Set<String> busy;
  final void Function(String userId) onApprove;
  final void Function(String userId) onReject;

  const _RequestsSection({
    required this.groupId,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(groupRequestsProvider(groupId));
    final requests = async.asData?.value ?? const <GroupMember>[];
    if (requests.isEmpty) return const SizedBox.shrink();

    return _GroupSection(
      title: 'Requests · ${requests.length}',
      children: [
        for (final r in requests)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                AvatarWidget(imageUrl: r.avatarUrl, size: 44, cacheScope: r.userId),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.nameOrFallback,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.textDark),
                      ),
                      if (r.major != null)
                        Text(r.major!, style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                if (busy.contains(r.userId))
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else ...[
                  // Approve is the action — brand blue, filled — not green: for the admin it is a
                  // decision to make, not a success to report.
                  _RequestIconButton(
                    icon: Icons.check_rounded,
                    filled: true,
                    tooltip: 'Approve ${r.nameOrFallback}',
                    onTap: () => onApprove(r.userId),
                  ),
                  _RequestIconButton(
                    icon: Icons.close_rounded,
                    filled: false,
                    tooltip: 'Decline ${r.nameOrFallback}',
                    onTap: () => onReject(r.userId),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _RequestIconButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final String tooltip;
  final VoidCallback onTap;
  const _RequestIconButton({
    required this.icon,
    required this.filled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          // 48dp target around a 36dp circle.
          child: SizedBox(
            width: kMinInteractiveDimension,
            height: kMinInteractiveDimension,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: filled ? AppColors.primary : const Color(0xFFEEF2F6),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: filled ? Colors.white : AppColors.textMid),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
