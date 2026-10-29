import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';

/// A DM partner's presence, as the server lets this viewer see it.
class PartnerPresence {
  const PartnerPresence({
    required this.userId,
    required this.visible,
    this.online = false,
    this.lastSeenAt,
  });

  final String userId;
  final bool visible;
  final bool online;
  final DateTime? lastSeenAt;

  factory PartnerPresence.fromJson(Map<String, dynamic> j) => PartnerPresence(
        userId: j['user_id'] as String,
        visible: j['visible'] as bool? ?? false,
        online: j['online'] as bool? ?? false,
        lastSeenAt: j['last_seen_at'] != null ? DateTime.parse(j['last_seen_at'] as String) : null,
      );
}

/// "Online" / "Last seen" for the partner of the DM addressed by `conversationRef` (protocol 5).
///
/// Fetched when the chat opens, then kept live by `presence` frames for that partner, and
/// refetched after a reconnect or an app resume (frames sent while the socket was down are gone).
/// Null on an older server, for a group, or on any error — the header then shows its usual line.
final partnerPresenceProvider =
    NotifierProvider.autoDispose.family<PartnerPresenceNotifier, PartnerPresence?, String>(
  PartnerPresenceNotifier.new,
);

class PartnerPresenceNotifier extends Notifier<PartnerPresence?> {
  PartnerPresenceNotifier(this.conversationRef);

  final String conversationRef;

  @override
  PartnerPresence? build() {
    final RealtimeClient rt;
    try {
      rt = ref.watch(realtimeClientProvider);
    } catch (_) {
      return null; // realtime unavailable (e.g. widget tests)
    }
    final events = rt.events.listen(_onEvent);
    final reconnects = rt.reconnected.listen((_) => _load(rt));
    final observer = _ResumeObserver(() => _load(rt));
    WidgetsBinding.instance.addObserver(observer);
    ref.onDispose(() {
      events.cancel();
      reconnects.cancel();
      WidgetsBinding.instance.removeObserver(observer);
    });
    Future.microtask(() => _load(rt));
    return null;
  }

  Future<void> _load(RealtimeClient rt) async {
    if (!rt.supportsProtocol(kPresenceProtocolVersion)) return;
    try {
      final resp = await ref.read(apiClientProvider).dio.get('/messages/threads/$conversationRef/presence');
      state = PartnerPresence.fromJson(Map<String, dynamic>.from(resp.data as Map));
    } catch (_) {
      // Not worth surfacing: the header falls back to its usual subtitle.
    }
  }

  void _onEvent(InboundEvent event) {
    final current = state;
    if (event is! PresenceEvent || current == null || event.userId != current.userId) return;
    state = PartnerPresence(
      userId: current.userId,
      visible: event.visible,
      online: event.visible && event.online,
      lastSeenAt: event.visible
          ? (event.lastSeenAt != null ? DateTime.tryParse(event.lastSeenAt!) : current.lastSeenAt)
          : null,
    );
  }
}

class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this.onResume);
  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
