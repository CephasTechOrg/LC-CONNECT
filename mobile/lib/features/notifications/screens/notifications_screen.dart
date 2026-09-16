import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../connections/providers/connections_provider.dart';
import '../data/notification_models.dart';
import '../providers/notifications_provider.dart';

/// The notification center. Unread rows stay visibly unread for the whole visit; opening one
/// marks just that one read.
///
/// Beta report #14 — "read/unread state is not visually clear enough". The unread chrome (tinted
/// row, bold title, dot) was all implemented but unreachable: the screen marked *everything* read
/// on mount, which raced the list refetch, so rows could come back already read and the styling
/// would flash off. The workaround was to pass `treatAsRead: true` for every row, which disabled
/// unread styling on the only screen that shows notifications.
///
/// The fix is [_unreadOnEntry]: snapshot which ids were unread *before* marking anything, and
/// style from the snapshot. That removes the race the workaround existed for **and** gives the
/// user time to see what was new — the two goals were never in conflict.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Ids that were unread when this screen opened. Styling reads from here, never from the
  /// live row state, so marking a row read does not make it look read mid-visit.
  final Set<String> _unreadOnEntry = {};
  bool _snapshotTaken = false;

  /// Ids the user has explicitly cleared with "Mark all read" during this visit.
  ///
  /// Needed because the list itself may still be stale — `markAllRead` triggers a refetch, but
  /// the styling must not wait on a network round trip to reflect a button the user just pressed.
  final Set<String> _clearedHere = {};

  /// The last rendered page, so "mark all read" knows which ids it just cleared.
  List<AppNotification> _items = const [];

  /// Records the unread set once, from the first loaded page.
  void _snapshot(List<AppNotification> items) {
    _items = items;
    if (_snapshotTaken) return;
    _snapshotTaken = true;
    _unreadOnEntry.addAll(items.where((n) => !n.read).map((n) => n.id));
  }

  /// A notification that arrives while the inbox is open is new to the user, so it counts as
  /// unread even though the snapshot was taken before it existed.
  bool _isUnread(AppNotification n) {
    if (_clearedHere.contains(n.id)) return false;
    return _unreadOnEntry.contains(n.id) || !n.read;
  }

  Future<void> _open(AppNotification n) async {
    final route = n.route;
    // Mark read first so the badge drops immediately; the row keeps its styling for this visit.
    if (!n.read) {
      await ref.read(notificationCountProvider.notifier).markOneRead(n.id);
    }
    if (!mounted || route == null) return;
    context.push(route);
  }

  Future<void> _markAllRead() async {
    // Everything currently on screen is cleared immediately; anything that arrives afterwards is
    // genuinely new and still shows as unread.
    final cleared = _items.map((n) => n.id).toList();
    setState(() => _clearedHere.addAll(cleared));
    await ref.read(notificationCountProvider.notifier).markAllRead();
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
        actions: [
          if (ref.watch(notificationCountProvider) > 0)
            TextButton(
              onPressed: _markAllRead,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                'Mark all read',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
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
              loading: () => const [
                AppThreadRowSkeleton(),
                AppThreadRowSkeleton(),
                AppThreadRowSkeleton(),
              ],
              error: (_, _) => [
                _Message(text: "Couldn't load notifications", onRetry: () => ref.invalidate(notificationsListProvider)),
              ],
              data: (items) {
                _snapshot(items);
                if (items.isEmpty) return [const _Message(text: "You're all caught up.")];
                return [
                  for (final n in items) ...[
                    _NotificationTile(
                      notification: n,
                      unread: _isUnread(n),
                      onOpen: () => _open(n),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                  ],
                ];
              },
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

  /// Supplied by the screen from its entry snapshot, not derived from `notification.read` — see
  /// [NotificationsScreen].
  final bool unread;
  final VoidCallback? onOpen;
  const _NotificationTile({
    required this.notification,
    this.unread = false,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final route = notification.route;
    return Semantics(
      // Unread is otherwise signalled only by a tint and a dot — both colour, neither available
      // to a screen reader.
      label: unread ? 'Unread. ${notification.message}' : notification.message,
      child: _tile(context, route),
    );
  }

  Widget _tile(BuildContext context, String? route) {
    return ListTile(
      onTap: onOpen ?? (route != null ? () => context.push(route) : null),
      tileColor: unread ? AppColors.primarySoft.withValues(alpha: 0.35) : null,
      leading: notification.isActorCentric
          ? AvatarWidget(imageUrl: notification.actorAvatarUrl, size: 40, cacheScope: notification.actorName)
          : CircleAvatar(
              backgroundColor: AppColors.primarySoft,
              child: Icon(_iconFor(notification.type), size: 20, color: AppColors.primary),
            ),
      title: Text(
        notification.message,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
          color: AppColors.textDark,
          height: 1.3,
        ),
      ),
      subtitle: Text(
        _timeAgo(notification.createdAt),
        style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unread)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            ),
          if (route != null) const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
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
      'admin_membership_invited' => Icons.admin_panel_settings_outlined,
      'program_membership_verified' => Icons.workspace_premium_outlined,
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
