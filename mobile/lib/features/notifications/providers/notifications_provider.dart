import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/notification_models.dart';

/// The unread-notifications badge counter. Mirrors the message unread pattern: seed from
/// `GET /notifications/unread-count` once a verified session exists, bump on live WS
/// `notification` events, re-seed on reconnect/app-resume, and zero it when the user opens the
/// notifications screen (mark-all-read).
final notificationCountProvider =
    NotifierProvider<NotificationCountNotifier, int>(NotificationCountNotifier.new);

class NotificationCountNotifier extends Notifier<int> {
  StreamSubscription<InboundEvent>? _eventsSub;
  StreamSubscription<void>? _reconnectSub;
  _ResumeObserver? _resumeObserver;

  @override
  int build() {
    final userId = ref.watch(authNotifierProvider.select((a) => a.asData?.value?.id));
    final client = ref.watch(realtimeClientProvider);

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
    if (event is NotificationEvent) state = state + 1;
  }

  /// Called when the notifications screen opens: clear the badge locally and mark all read
  /// on the server. If the call fails, the next re-seed restores the true count.
  Future<void> markAllRead() async {
    state = 0;
    try {
      await ref.read(apiClientProvider).dio.post('/notifications/read');
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
