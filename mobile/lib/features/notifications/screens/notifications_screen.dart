import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../data/notification_models.dart';
import '../providers/notifications_provider.dart';

/// The notification center — a list of group membership events. Opening it marks everything read
/// (the bell badge clears); tapping a row jumps to the related group.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Viewing the screen clears the badge + marks read on the server.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationCountProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsListProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Notifications',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: AppColors.textDark)),
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          text: "Couldn't load notifications",
          onRetry: () => ref.invalidate(notificationsListProvider),
        ),
        data: (items) => items.isEmpty
            ? const _Message(text: "You're all caught up.")
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsListProvider),
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) => _NotificationTile(notification: items[i]),
                ),
              ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final gid = notification.groupId;
    return ListTile(
      onTap: gid != null ? () => context.push('/groups/$gid') : null,
      leading: CircleAvatar(
        backgroundColor: AppColors.primarySoft,
        child: Icon(_iconFor(notification.type), size: 20, color: AppColors.primary),
      ),
      title: Text(
        notification.message,
        style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.textDark, height: 1.3),
      ),
      subtitle: Text(
        _timeAgo(notification.createdAt),
        style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
      ),
      trailing: gid != null
          ? const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted)
          : null,
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const _Message({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: GoogleFonts.dmSans(color: AppColors.textMuted)),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('Retry', style: GoogleFonts.dmSans(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

IconData _iconFor(String type) => switch (type) {
      'group_invite' => Icons.mark_email_unread_outlined,
      'group_request_approved' => Icons.check_circle_outline_rounded,
      'group_request_rejected' => Icons.cancel_outlined,
      'group_made_admin' => Icons.shield_outlined,
      'group_removed_admin' => Icons.remove_moderator_outlined,
      'group_removed' => Icons.person_remove_outlined,
      'group_join_request' => Icons.group_add_outlined,
      _ => Icons.notifications_outlined,
    };

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}
