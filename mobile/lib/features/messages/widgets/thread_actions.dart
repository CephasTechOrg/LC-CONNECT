part of '../screens/messages_screen.dart';

/// Long-press on an inbox row: pin, archive and mute, as in WhatsApp. Each is optimistic and
/// syncs to your other devices; pin and archive need a protocol-6 server, mute protocol 5.
void showThreadActions(BuildContext context, WidgetRef ref, MessageThread thread, {required int unread}) {
  final rt = ref.read(realtimeClientProvider);
  final inbox = rt.supportsProtocol(kInboxProtocolVersion);
  final notifier = ref.read(threadsNotifierProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);

  Future<void> run(Future<void> Function() action, String done) async {
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(apiErrorMessage(e, fallback: "Couldn't update this chat. Try again.")),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheet) {
      Widget tile(IconData icon, String label, VoidCallback onTap) => ListTile(
            leading: Icon(icon, color: AppColors.textMid),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDark)),
            onTap: () {
              Navigator.of(sheet).pop();
              onTap();
            },
          );
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                thread.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textDark),
              ),
            ),
            if (inbox && !thread.archived)
              tile(
                thread.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                thread.pinned ? 'Unpin chat' : 'Pin chat',
                () => run(
                  () => notifier.setPinned(thread.addressingId, !thread.pinned),
                  thread.pinned ? 'Chat unpinned' : 'Chat pinned',
                ),
              ),
            if (inbox)
              tile(
                thread.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                thread.archived ? 'Unarchive chat' : 'Archive chat',
                () => run(
                  () => notifier.setArchived(thread.addressingId, !thread.archived),
                  thread.archived ? 'Chat moved back to your inbox' : 'Chat archived',
                ),
              ),
            if (rt.supportsProtocol(kMuteProtocolVersion))
              tile(
                thread.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
                thread.muted ? 'Unmute notifications' : 'Mute notifications',
                () => run(
                  () => notifier.setMuted(thread.addressingId, !thread.muted),
                  thread.muted ? 'Chat unmuted' : 'Chat muted',
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
