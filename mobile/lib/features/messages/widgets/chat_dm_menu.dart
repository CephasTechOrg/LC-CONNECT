part of '../screens/chat_screen.dart';

/// The ⋮ menu of a DM: mute, the partner's profile, and the safety actions. It used to open the
/// block/report sheet directly, which left nowhere to put a mute switch.
extension _ChatDmMenu on _ChatScreenState {
  bool get dmMuted => ref
          .watch(threadsNotifierProvider)
          .asData
          ?.value
          .where((t) => t.addressingId == widget.matchId)
          .firstOrNull
          ?.muted ??
      false;

  void openDmMenu(MessagePartner partner) {
    final muted = dmMuted;
    final canMute = rt.supportsProtocol(kMuteProtocolVersion);
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpacing.sm),
            if (canMute)
              _menuTile(
                icon: muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                title: muted ? 'Unmute notifications' : 'Mute notifications',
                subtitle: muted
                    ? 'Get notified about new messages again'
                    : 'No alerts for messages or reactions. You still see them here.',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _setMuted(!muted);
                },
              ),
            _menuTile(
              icon: Icons.person_outline_rounded,
              title: 'View profile',
              onTap: () {
                Navigator.of(sheetCtx).pop();
                context.push('/users/${partner.profileId}', extra: partner.displayName);
              },
            ),
            _menuTile(
              icon: Icons.shield_outlined,
              title: 'Block or report',
              danger: true,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                showSafetySheet(
                  context: context,
                  targetUserId: partner.userId,
                  targetName: partner.displayName ?? 'this student',
                  safetyService: ref.read(safetyServiceProvider),
                  onBlocked: () {
                    if (mounted) context.go('/messages');
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _setMuted(bool muted) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(threadsNotifierProvider.notifier).setMuted(widget.matchId, muted);
      messenger.showSnackBar(SnackBar(
        content: Text(muted ? 'Chat muted' : 'Chat unmuted'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't change notifications. Try again."),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool danger = false,
    required VoidCallback onTap,
  }) {
    final color = danger ? AppColors.error : AppColors.textDark;
    return ListTile(
      leading: Icon(icon, color: danger ? AppColors.error : AppColors.textMid),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w400, color: AppColors.textMuted)),
      onTap: onTap,
    );
  }
}
