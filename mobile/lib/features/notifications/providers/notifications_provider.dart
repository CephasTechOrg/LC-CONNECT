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
    _resumeObserver = _ResumeObserver(_seed);
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
    } catch (_) {/* keep current; next reconnect/resume re-seeds */}
  }

  void _onEvent(InboundEvent event) {
    if (event is! NotificationEvent) return;
    state = state + 1;
    // Inbox open? Pull the new row in without waiting for pull-to-refresh.
    ref.invalidate(notificationsListProvider);
  }

  /// Called when the notifications screen opens: clear the badge locally and mark all read
  /// on the server. If the call fails, the next re-seed restores the true count.
  Future<void> markAllRead() async {
    state = 0;
    try {
      await ref.read(apiClientProvider).dio.post('/notifications/read');
      ref.invalidate(notificationsListProvider);
    } catch (_) {/* re-seed will correct on next reconnect/resume */}
  }
}

/// The notification list for the screen. Autoloads the newest notifications.
final notificationsListProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final resp = await ref.read(apiClientProvider).dio.get('/notifications');
  return (resp.data as List)
      .map((j) => AppNotification.fromJson(j as Map<String, dynamic>))
      .toList();
});

class _ResumeObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _ResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
