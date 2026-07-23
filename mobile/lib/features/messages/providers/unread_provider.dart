import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../auth/providers/auth_provider.dart';

/// Single source of truth for unread message counts. Both the nav badge and the
/// per-conversation row badges read from here, so they can never drift.
///
/// Backend is authoritative: we seed from `GET /messages/unread-summary` (after a
/// verified session exists), then keep a live mirror via WS `conversation.updated`,
/// and re-seed on reconnect + app-resume so any drift self-corrects.
class UnreadState {
  final int total;
  final Map<String, int> perConversation;

  /// The conversation currently open on screen — messages arriving here are being
  /// read live, so they must not inflate the badge.
  final String? activeConversationId;

  const UnreadState({
    this.total = 0,
    this.perConversation = const {},
    this.activeConversationId,
  });

  int countFor(String matchId) => perConversation[matchId] ?? 0;

  UnreadState copyWith({
    int? total,
    Map<String, int>? perConversation,
    String? activeConversationId,
    bool clearActive = false,
  }) =>
      UnreadState(
        total: total ?? this.total,
        perConversation: perConversation ?? this.perConversation,
        activeConversationId:
            clearActive ? null : (activeConversationId ?? this.activeConversationId),
      );
}

final unreadProvider =
    NotifierProvider<UnreadNotifier, UnreadState>(UnreadNotifier.new);

class UnreadNotifier extends Notifier<UnreadState> {
  StreamSubscription<InboundEvent>? _eventsSub;
  StreamSubscription<void>? _reconnectSub;
  _ResumeObserver? _resumeObserver;

  @override
  UnreadState build() {
    // Rebuild only when the *user* changes (sign-in/out), not on every token refresh.
    final userId = ref.watch(authNotifierProvider.select((a) => a.asData?.value?.id));
    final client = ref.watch(realtimeClientProvider);

    _eventsSub = client.events.listen(_onEvent);
    _reconnectSub = client.reconnected.listen((_) => _seed()); // socket came back → resync
    _resumeObserver = _ResumeObserver(_seed);
    WidgetsBinding.instance.addObserver(_resumeObserver!);

    ref.onDispose(() {
      _eventsSub?.cancel();
      _reconnectSub?.cancel();
      if (_resumeObserver != null) {
        WidgetsBinding.instance.removeObserver(_resumeObserver!);
      }
    });

    // Seed only for a verified/authenticated session (the endpoint is gated). Signed
    // out → zero. `_seed` mutates state asynchronously once the request returns.
    if (userId != null) _seed();
    return const UnreadState();
  }

  String? get _myId => ref.read(authNotifierProvider).asData?.value?.id;

  Future<void> _seed() async {
    if (_myId == null) return; // not authenticated → nothing to fetch
    try {
      final resp = await ref.read(apiClientProvider).dio.get('/messages/unread-summary');
      final data = resp.data as Map<String, dynamic>;
      final per = <String, int>{
        for (final e in (data['per_conversation'] as Map<String, dynamic>).entries)
          e.key: (e.value as num).toInt(),
      };
      state = state.copyWith(total: (data['total'] as num).toInt(), perConversation: per);
    } catch (_) {
      // Keep the current mirror; the next reconnect/resume seed will correct it.
    }
  }

  void _onEvent(InboundEvent event) {
    if (event is! ConversationUpdated) return;
    // "Ignore own" reads sender_id straight from the message payload (reliable).
    final senderId = event.message['sender_id'] as String?;
    if (senderId == null || senderId == _myId) return;
    if (event.conversationId == state.activeConversationId) return; // read live in the open chat

    final per = Map<String, int>.from(state.perConversation);
    per[event.conversationId] = (per[event.conversationId] ?? 0) + 1;
    state = state.copyWith(total: state.total + 1, perConversation: per);
  }

  /// Called when a chat opens — marks it active so live messages don't inflate the badge.
  void enterConversation(String matchId) =>
      state = state.copyWith(activeConversationId: matchId);

  void leaveConversation() => state = state.copyWith(clearActive: true);

  /// Optimistically zero a conversation's unread (on top of the real WS `messages.read`).
  /// If the read call fails, the next re-seed restores the true count.
  void clearConversation(String matchId) {
    final n = state.perConversation[matchId] ?? 0;
    if (n == 0) return;
    final per = Map<String, int>.from(state.perConversation)..[matchId] = 0;
    state = state.copyWith(
      total: (state.total - n).clamp(0, 1 << 31),
      perConversation: per,
    );
  }
}

/// Re-seeds unread counts when the app returns to the foreground.
class _ResumeObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;
  _ResumeObserver(this.onResume);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
