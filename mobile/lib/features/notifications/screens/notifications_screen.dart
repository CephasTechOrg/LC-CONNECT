import 'dart:async';

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
import '../../../shared/util/caching.dart';

part '../widgets/notification_rows.dart';

/// The notification center. Unread rows are tinted until opened; opening one marks just that one
/// read and untints it at once.
///
/// Beta report #14 made unread state visible (the screen used to mark everything read on mount).
/// A later fix kept opened rows tinted for the rest of the visit from a snapshot taken on entry,
/// but that read as "I tapped it and it is still unread", and the cached list never learned the
/// row was read, so it came back unread on the next visit. Rows now style from their own `read`,
/// which the count notifier flips in the cached list before the request goes out.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Ids the user has explicitly cleared with "Mark all read" during this visit.
  ///
  /// Needed because the list itself may still be stale — `markAllRead` triggers a refetch, but
  /// the styling must not wait on a network round trip to reflect a button the user just pressed.
  final Set<String> _clearedHere = {};

  /// The last rendered page, so "mark all read" knows which ids it just cleared.
  List<AppNotification> _items = const [];

  @override
  void initState() {
    super.initState();
    // The list is cached across visits (keepAlive), so refresh behind the cached rows on open:
    // read state changed elsewhere (another device, a chat opened) shows up without a pull.
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(notificationsListProvider).hasValue) {
        ref.read(notificationsListProvider.notifier).refresh();
      }
    });
  }

  bool _isUnread(AppNotification n) => !n.read && !_clearedHere.contains(n.id);

  void _open(AppNotification n) {
    // Mark read without waiting: the row and badge change locally first, and navigation must not
    // sit behind a network round trip.
    if (!n.read) unawaited(ref.read(notificationCountProvider.notifier).markOneRead(n.id));
    final route = n.route;
    if (route != null) context.push(route);
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
              ...async.cached(
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
                  _items = items;
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
