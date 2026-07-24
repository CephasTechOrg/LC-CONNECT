import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../connections/providers/connections_provider.dart';
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsListProvider);
          ref.invalidate(connectionsNotifierProvider);
        },
        child: ListView(
          children: [
            const _ConnectionRequestsRow(), // pinned: always the way into Connections
            const Divider(height: 1, color: AppColors.border),
            ...async.when(
              loading: () => [const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator()))],
              error: (_, _) => [
                _Message(text: "Couldn't load notifications", onRetry: () => ref.invalidate(notificationsListProvider)),
              ],
              data: (items) => items.isEmpty
                  ? [const _Message(text: "You're all caught up.")]
                  : [
                      for (final n in items) ...[
                        _NotificationTile(notification: n),
                        const Divider(height: 1, color: AppColors.border),
                      ],
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pinned entry to the Connections screen, with a live count of pending incoming requests.
class _ConnectionRequestsRow extends ConsumerWidget {
  const _ConnectionRequestsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(connectionsNotifierProvider).asData?.value.incoming.length ?? 0;
    return ListTile(
      onTap: () => context.push('/connections'),
      leading: const CircleAvatar(
        backgroundColor: AppColors.primarySoft,
        child: Icon(Icons.people_alt_outlined, size: 20, color: AppColors.primary),
      ),
      title: Text(
        'Connection requests',
        style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark),
      ),
      subtitle: Text(
        count > 0 ? '$count pending' : 'View sent & received',
        style: GoogleFonts.dmSans(fontSize: 12, color: count > 0 ? AppColors.primary : AppColors.textMuted),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final route = notification.route;
    return ListTile(
      onTap: route != null ? () => context.push(route) : null,
      leading: notification.isActorCentric
          ? AvatarWidget(imageUrl: notification.actorAvatarUrl, size: 40, cacheScope: notification.actorName)
          : CircleAvatar(
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
      trailing: route != null
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
      'connection_request' => Icons.person_add_alt_1_outlined,
      'connection_accepted' => Icons.how_to_reg_outlined,
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
