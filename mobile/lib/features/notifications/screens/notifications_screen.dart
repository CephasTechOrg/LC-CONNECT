import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../connections/providers/connections_provider.dart';
import '../data/notification_models.dart';
import '../providers/notifications_provider.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/util/app_date_format.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

part '../widgets/notification_rows.dart';

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
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
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

  /// The list, with a day header wherever the calendar day changes.
  ///
  /// Report #15: the inbox was a flat list, so "three days ago" and "two minutes ago" sat
  /// together with only a relative timestamp to tell them apart. Grouping is what makes a long
  /// history skimmable.
  ///
  /// Uses `AppDateFormat.daySeparator` — the same helper the chat date separators use — rather
  /// than a second Today/Yesterday rule. Two rules would eventually disagree, and a reader would
  /// see the same day labelled differently on two screens.
  ///
  /// Each day's rows sit in one card under their heading.
  List<Widget> _grouped(List<AppNotification> items) {
    final sections = <Widget>[];
    var dayRows = <Widget>[];
    DateTime? currentDay;

    void closeDay() {
      if (dayRows.isNotEmpty) sections.add(_DayCard(rows: dayRows));
      dayRows = <Widget>[];
    }

    for (final n in items) {
      final day = AppDateFormat.dayBucket(n.createdAt);
      if (currentDay == null || day != currentDay) {
        closeDay();
        currentDay = day;
        sections.add(_DayHeader(label: AppDateFormat.daySeparator(n.createdAt)));
      }
      dayRows.add(_NotificationTile(
        notification: n,
        unread: _isUnread(n),
        onOpen: () => _open(n),
      ));
    }
    closeDay();
    return sections;
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
        title: Text(
          'Notifications',
          style: AppTypography.title.copyWith(color: AppColors.textDark),
        ),
        iconTheme: const IconThemeData(color: AppColors.textDark),
        actions: [
          if (ref.watch(notificationCountProvider) > 0)
            TextButton(
              onPressed: _markAllRead,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                'Mark all read',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryText,
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        // `refresh()` rather than `invalidate`: the provider is keepAlive so the rows stay on
        // screen while it re-reads, instead of collapsing to a skeleton.
        onRefresh: () async {
          ref.invalidate(connectionsNotifierProvider);
          await ref.read(notificationsListProvider.notifier).refresh();
        },
        child: NotificationListener<ScrollNotification>(
          // Older notifications are now paged rather than capped at a single fixed request, so
          // the list has to be able to ask for the next page.
          onNotification: (notification) {
            if (notification.metrics.extentAfter < 400) {
              ref.read(notificationsListProvider.notifier).loadMore();
            }
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.lg,
              AppSpacing.gutter,
              AppSpacing.xxl,
            ),
            children: [
              const _ConnectionRequestsCard(), // pinned: always the way into Connections
              ...async.when(
                loading: () => const [
                  AppThreadRowSkeleton(),
                  AppThreadRowSkeleton(),
                  AppThreadRowSkeleton(),
                ],
                error: (_, _) => [
                  AppInlineMessage(
                    message: "Couldn't load notifications",
                    onRetry: () =>
                        ref.read(notificationsListProvider.notifier).refresh(),
                  ),
                ],
                data: (items) {
                  _snapshot(items);
                  if (items.isEmpty) {
                    return [const AppInlineMessage(message: "You're all caught up.")];
                  }
                  return _grouped(items);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
