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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Requests (${requests.length})',
            style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
          ),
        ),
        for (final r in requests)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                AvatarWidget(imageUrl: r.avatarUrl, size: 40, cacheScope: r.userId),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.nameOrFallback,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textDark),
                      ),
                      if (r.major != null)
                        Text(r.major!, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ),
                ),
                if (busy.contains(r.userId))
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else ...[
                  _RequestIconButton(
                    icon: Icons.check_rounded,
                    color: AppColors.green,
                    onTap: () => onApprove(r.userId),
                  ),
                  const SizedBox(width: 6),
                  _RequestIconButton(
                    icon: Icons.close_rounded,
                    color: AppColors.textMuted,
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
  final Color color;
  final VoidCallback onTap;
  const _RequestIconButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(24),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(padding: const EdgeInsets.all(7), child: Icon(icon, size: 20, color: color)),
      ),
    );
  }
}
