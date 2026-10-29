import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/notification_models.dart';

/// The unread-notifications badge counter.
///
/// Product model (same family as Opportunities, not Announcements):
/// - Opening the inbox marks **all** read and clears the badge.
/// - Unlike announcements, you do **not** need to tap each row for the count to drop.
///
/// Reliability: keepAlive so WS +1 still works when the bell isn't mounted; invalidate the
/// list on a live event so an open inbox updates without pull-to-refresh.
final notificationCountProvider =
    NotifierProvider<NotificationCountNotifier, int>(NotificationCountNotifier.new);

class NotificationCountNotifier extends Notifier<int> {
  StreamSubscription<InboundEvent>? _eventsSub;
  StreamSubscription<void>? _reconnectSub;
  _ResumeObserver? _resumeObserver;

  /// Ids already subtracted from the badge since the last server re-seed. Opening the same row
  /// twice (or from two places) must drop the count once — it used to drop it every time, so the
  /// badge under-counted until the next resume.
  final _countedRead = <String>{};

  @override
  int build() {
    // Same trap as announcementCountProvider: without keepAlive the listener dies when the
    // Campus Hub header unmounts, and the next WS ping never increments until something re-watches.
    ref.keepAlive();
    final userId = ref.watch(authNotifierProvider.select((a) => a.asData?.value?.id));
    final RealtimeClient client;
    try {
      client = ref.watch(realtimeClientProvider);
    } catch (_) {
      return 0; // realtime/env unavailable (e.g. widget tests) — degrade to no badge
    }

    _eventsSub = client.events.listen(_onEvent);
    _reconnectSub = client.reconnected.listen((_) => _seed());
    _resumeObserver = _ResumeObserver(_onResume);
    WidgetsBinding.instance.addObserver(_resumeObserver!);

    ref.onDispose(() {
      _eventsSub?.cancel();
      _reconnectSub?.cancel();
      if (_resumeObserver != null) WidgetsBinding.instance.removeObserver(_resumeObserver!);
    });

    if (userId != null) _seed();
    return 0;
  }

  bool get _authed => ref.read(authNotifierProvider).asData?.value?.id != null;

  Future<void> _seed() async {
    if (!_authed) return;
    try {
      final resp = await ref.read(apiClientProvider).dio.get('/notifications/unread-count');
      state = ((resp.data as Map<String, dynamic>)['count'] as num).toInt();
      _countedRead.clear();
    } catch (_) {/* keep current; next reconnect/resume re-seeds */}
  }

  /// Back in the foreground: re-seed the badge **and** the list, so the two cannot drift apart
  /// (the badge used to refresh here while the rows kept their stale read state).
  void _onResume() {
    _seed();
    final list = ref.read(notificationsListProvider);
    if (list.hasValue) ref.read(notificationsListProvider.notifier).refresh();
  }

  void _onEvent(InboundEvent event) {
    if (event is! NotificationEvent) return;
    final AppNotification row;
    try {
      row = AppNotification.fromJson(event.notification);
    } catch (_) {
      // Malformed or unknown payload — the next refresh will pick it up properly.
      state = state + 1;
      ref.invalidate(notificationsListProvider);
      return;
    }
    // Insert the row we were just handed rather than refetching the page for it. A frame for a
    // row we already have (a collapsed reaction updating its emoji) replaces it in place and is
    // not a new unread.
    final isNew = ref.read(notificationsListProvider.notifier).upsert(row);
    if (isNew != false && !row.read) state = state + 1;
  }

  /// Explicit "mark all read" action. Clears the badge locally, then the server.
  ///
  /// This used to run automatically when the inbox mounted, which is what made unread state
  /// invisible: everything was read before the user could look at it, so the screen had to
  /// suppress unread styling entirely to avoid flashing it off mid-refetch.
  Future<void> markAllRead() async {
    state = 0;
    try {
      await ref.read(apiClientProvider).dio.post('/notifications/read');
      await ref.read(notificationsListProvider.notifier).refresh();
    } catch (_) {/* re-seed will correct on next reconnect/resume */}
  }

  /// Marks one notification read when the user opens it: the row and the badge change together,
  /// before the request, and the badge drops by exactly one.
  ///
  /// The row used to keep `read: false` in the cached list (only the count changed), so it was
  /// unread again the next time the inbox opened, and opening it again subtracted a second time.
  /// Idempotent server-side; any remaining drift is corrected by the reconnect/resume re-seed.
  Future<void> markOneRead(String notificationId) async {
    final wasUnread = ref.read(notificationsListProvider.notifier).markReadLocally(notificationId);
    if (wasUnread != false && _countedRead.add(notificationId) && state > 0) state = state - 1;
    try {
      await ref.read(apiClientProvider).dio.post('/notifications/$notificationId/read');
    } catch (_) {/* re-seed will correct on next reconnect/resume */}
  }
}

/// The notification list for the screen.
///
/// `keepAlive`, not `autoDispose`: every open of the inbox was a cold fetch behind a skeleton,
/// with no cached first paint, which is most of what made the screen feel slow (#13). Cached rows
/// render immediately and a refresh runs behind them.
final notificationsListProvider =
    AsyncNotifierProvider<NotificationsListNotifier, List<AppNotification>>(
  NotificationsListNotifier.new,
);

class NotificationsListNotifier extends AsyncNotifier<List<AppNotification>> {
  /// Rows per page. The endpoint caps at 100.
  static const pageSize = 30;

  bool _reachedEnd = false;

  /// Whether every page has been loaded.
  bool get reachedEnd => _reachedEnd;

  @override
  Future<List<AppNotification>> build() async {
    ref.keepAlive();
    ref.watch(authNotifierProvider);
    return _fetch();
  }

  Future<List<AppNotification>> _fetch({AppNotification? after}) async {
    final resp = await ref.read(apiClientProvider).dio.get(
      '/notifications',
      queryParameters: {
        'limit': pageSize,
        if (after != null) ...{
          'before_created_at': after.createdAt.toUtc().toIso8601String(),
          'before_id': after.id,
        },
      },
    );
    final rows = (resp.data as List)
        .map((j) => AppNotification.fromJson(j as Map<String, dynamic>))
        .toList();
    if (rows.length < pageSize) _reachedEnd = true;
    return rows;
  }

  /// Re-reads the newest page, keeping the current rows visible while it runs.
  Future<void> refresh() async {
    _reachedEnd = false;
    state = await AsyncValue.guard(_fetch);
  }

  /// Appends the next page. No-op once everything is loaded or while a load is in flight.
  Future<void> loadMore() async {
    final current = state.value;
    if (_reachedEnd || current == null || current.isEmpty || state.isLoading) return;
    try {
      final next = await _fetch(after: current.last);
      final known = current.map((n) => n.id).toSet();
      state = AsyncData([...current, ...next.where((n) => !known.contains(n.id))]);
    } catch (_) {/* keep what we have; the user can pull to refresh */}
  }

  /// Inserts (or updates in place) a notification that arrived over the WebSocket.
  ///
  /// The frame already carries the full serialized row — the same shape `GET /notifications`
  /// returns — so refetching the whole page per event was pure waste. With the inbox open, ten
  /// notifications meant ten full list requests.
  ///
  /// Returns true when the row is new, false when it replaced one already listed, and null when
  /// nothing is loaded yet (the first fetch will include it).
  bool? upsert(AppNotification notification) {
    final current = state.value;
    if (current == null) return null;
    final i = current.indexWhere((n) => n.id == notification.id);
    if (i == -1) {
      state = AsyncData([notification, ...current]);
      return true;
    }
    state = AsyncData([...current]..[i] = notification);
    return false;
  }

  /// Flips one cached row to read, so it untints the moment it is opened rather than after the
  /// next refetch. Returns whether it was unread, or null when the row is not loaded.
  bool? markReadLocally(String id) {
    final current = state.value;
    if (current == null) return null;
    final i = current.indexWhere((n) => n.id == id);
    if (i == -1) return null;
    final wasUnread = !current[i].read;
    if (wasUnread) state = AsyncData([...current]..[i] = current[i].copyWith(read: true));
    return wasUnread;
  }

  /// Flips several cached rows to read (another device or opening a chat read them).
  void markManyReadLocally(Iterable<String> ids) {
    final current = state.value;
    final targets = ids.toSet();
    if (current == null || targets.isEmpty) return;
    state = AsyncData([
      for (final n in current) targets.contains(n.id) && !n.read ? n.copyWith(read: true) : n,
    ]);
  }

  /// Drops a row the server retracted (an un-reacted reaction the user never saw).
  void remove(String id) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData([for (final n in current) if (n.id != id) n]);
  }
}

class _ResumeObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _ResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
