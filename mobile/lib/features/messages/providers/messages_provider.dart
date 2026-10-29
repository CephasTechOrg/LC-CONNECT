import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/message_models.dart';
import '../data/thread_models.dart';

export '../data/message_models.dart';
export '../data/thread_models.dart';

// ── Thread list provider ──────────────────────────────────────────
final threadsNotifierProvider =
    AsyncNotifierProvider<ThreadsNotifier, List<MessageThread>>(
        ThreadsNotifier.new);

class ThreadsNotifier extends AsyncNotifier<List<MessageThread>> {
  StreamSubscription<InboundEvent>? _sub;
  final _typingTimers = <String, Timer>{};
  Timer? _refreshDebounce;
  String _myId = '';

  @override
  Future<List<MessageThread>> build() async {
    ref.watch(authNotifierProvider.select((auth) => auth.asData?.value?.id));
    final client = ref.watch(apiClientProvider);
    // Watching the client ensures the socket connects; user-channel
    // `conversation.updated` + `typing` events keep this list live.
    final realtime = ref.watch(realtimeClientProvider);
    _myId = ref.read(authNotifierProvider).asData?.value?.id ?? '';
    _sub = realtime.events.listen((event) {
      switch (event) {
        case ConversationUpdated():
          _onConversationUpdated(event);
        case TypingEvent():
          _onTyping(event);
        // A protocol-5 server also sends the richer state frame below; this one would only
        // overwrite its snippet and actor name.
        case ReactionActivity() when !realtime.supportsProtocol(kReactorsProtocolVersion):
          _onReactionActivity(event);
        case ReactionEvent():
          _onReaction(event);
        case MessageEdited():
          _onEdited(event);
        case MessageDeleted():
          _onDeleted(event);
        case ConversationMuted():
          _updateThread(event.conversationId, (t) => t.copyWith(muted: event.muted));
        case ConversationState():
          final pinnedAt = DateTime.tryParse(event.pinnedAt ?? '');
          _updateThread(
            event.conversationId,
            (t) => t.copyWith(pinnedAt: pinnedAt, clearPinnedAt: pinnedAt == null, archived: event.archived),
          );
        case PresenceEvent():
          _onPresence(event);
        default:
          break;
      }
    });
    ref.onDispose(() {
      _sub?.cancel();
      _refreshDebounce?.cancel();
      for (final t in _typingTimers.values) {
        t.cancel();
      }
    });

    return _fetch(client);
  }

  Future<List<MessageThread>> _fetch(ApiClient api) async {
    final response = await api.dio.get('/messages/threads');
    return (response.data as List)
        .map((j) => MessageThread.fromJson(j as Map<String, dynamic>))
        .where((t) => t.isGroup || t.partner != null) // keep group + valid DM threads
        // Staff can open a student chat before sending anything. Keep those empty staff threads
        // out of the inbox until the first real message exists.
        .where((t) => !t.isStaffThread || t.latestMessage != null)
        .toList();
  }

  void _onConversationUpdated(ConversationUpdated event) {
    final current = state.asData?.value;
    if (current == null) return;

    final idx = current.indexWhere((t) => t.addressingId == event.conversationId);
    if (idx == -1) {
      // A thread we don't have yet — a new match, or a staff member messaging us out of the
      // blue. Refetch so it appears in the inbox immediately instead of on next open.
      ref.invalidateSelf();
      return;
    }

    _typingTimers.remove(event.conversationId)?.cancel(); // a new message clears typing
    final msg = ChatMessage.fromJson(event.message);
    final updated = List<MessageThread>.from(current);
    updated[idx] = current[idx].copyWith(latestMessage: msg, partnerTyping: false);
    updated.sort((a, b) {
      final aTime = a.latestMessage?.createdAt;
      final bTime = b.latestMessage?.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    state = AsyncData(updated);
  }

  /// A reaction to one of my messages arrived (protocol 4). Decorate the thread's row in place —
  /// deliberately **no re-sort**: a reaction is not new-message activity and must not jump a
  /// thread to the top. The row's subtitle decides whether to show it (see `_preview`).
  void _onReactionActivity(ReactionActivity event) {
    final current = state.asData?.value;
    if (current == null) return;
    final idx = current.indexWhere((t) => t.addressingId == event.conversationId);
    if (idx == -1) return; // a thread we don't have loaded — REST will seed it on next open
    final updated = List<MessageThread>.from(current);
    updated[idx] = current[idx].copyWith(
      latestReaction: ThreadReactionPreview(
        emoji: event.emoji,
        actorId: event.actorId,
        messageId: event.messageId,
        reactedAt: DateTime.tryParse(event.reactedAt) ?? DateTime.now(),
      ),
    );
    state = AsyncData(updated);
  }

  void _updateThread(String addressingId, MessageThread Function(MessageThread) change) {
    final current = state.asData?.value;
    if (current == null) return;
    final idx = current.indexWhere((t) => t.addressingId == addressingId);
    if (idx == -1) return;
    final updated = List<MessageThread>.from(current);
    updated[idx] = change(current[idx]);
    state = AsyncData(updated);
  }

  /// A reaction changed somewhere (protocol 5 state frame, on every member's user channel). The
  /// row shows it when it is a reaction worth showing (any in a DM; in a group, to or by me) — it
  /// never moves the row. An un-react that clears the reaction the row is showing refetches the
  /// list quietly, so the row falls back to whatever is now newest.
  void _onReaction(ReactionEvent event) {
    final conversationId = event.conversationId;
    if (!event.isStateful || conversationId == null) return;
    final current = state.asData?.value;
    final thread = current?.where((t) => t.addressingId == conversationId).firstOrNull;
    if (thread == null) return;
    if (event.userEmoji == null) {
      final shown = thread.latestReaction;
      if (shown != null && shown.messageId == event.messageId && shown.actorId == event.userId) {
        _refreshDebounce?.cancel();
        _refreshDebounce = Timer(const Duration(seconds: 1), _refreshSilently);
      }
      return;
    }
    final relevant =
        !thread.isGroup || event.messageSenderId == _myId || event.userId == _myId;
    if (!relevant) return;
    _updateThread(
      conversationId,
      (t) => t.copyWith(
        latestReaction: ThreadReactionPreview(
          emoji: event.userEmoji!,
          actorId: event.userId,
          actorName: event.actorName,
          messageId: event.messageId,
          messageSenderId: event.messageSenderId,
          messageSnippet: event.messageSnippet ?? '',
          reactedAt: DateTime.tryParse(event.reactedAt ?? '') ?? DateTime.now(),
        ),
      ),
    );
  }

  /// An edit to the row's latest message (or to the message its reaction quotes) changes what the
  /// row says. The row used to keep the old text until the next full refresh.
  void _onEdited(MessageEdited event) {
    _updateThread(event.conversationId, (t) {
      var next = t;
      final latest = t.latestMessage;
      if (latest != null && latest.id == event.messageId) {
        next = next.copyWith(
          latestMessage: latest.copyWith(body: event.body, editedAt: DateTime.tryParse(event.editedAt)),
        );
      }
      final reaction = t.latestReaction;
      if (reaction != null && reaction.messageId == event.messageId) {
        next = next.copyWith(latestReaction: reaction.copyWith(messageSnippet: oneLine(event.body)));
      }
      return next;
    });
  }

  /// A deleted latest message reads "This message was deleted" (it used to read blank), and a
  /// reaction to a deleted message is no longer worth a line.
  void _onDeleted(MessageDeleted event) {
    _updateThread(event.conversationId, (t) {
      var next = t;
      final latest = t.latestMessage;
      if (latest != null && latest.id == event.messageId) {
        next = next.copyWith(latestMessage: latest.copyWith(deleted: true, body: ''));
      }
      if (t.latestReaction?.messageId == event.messageId) {
        next = next.copyWith(clearLatestReaction: true);
      }
      return next;
    });
  }

  Future<void> _refreshSilently() async {
    try {
      final fresh = await _fetch(ref.read(apiClientProvider));
      final typing = {
        for (final t in state.asData?.value ?? const <MessageThread>[])
          if (t.partnerTyping) t.addressingId,
      };
      state = AsyncData([
        for (final t in fresh) typing.contains(t.addressingId) ? t.copyWith(partnerTyping: true) : t,
      ]);
    } catch (_) {/* keep the current rows; the next open refreshes */}
  }

  /// A connection came online or went offline: the dot on every DM row with them.
  void _onPresence(PresenceEvent event) {
    final current = state.asData?.value;
    if (current == null) return;
    final online = event.visible && event.online;
    if (!current.any((t) => t.partner?.userId == event.userId && t.partnerOnline != online)) return;
    state = AsyncData([
      for (final t in current) t.partner?.userId == event.userId ? t.copyWith(partnerOnline: online) : t,
    ]);
  }

  /// Pin or unpin a chat for myself — optimistic, rolled back if the server refuses (a fourth pin
  /// is a 409, which the caller shows).
  Future<void> setPinned(String addressingId, bool pinned) =>
      _setState(addressingId, {'pinned': pinned}, (t) => pinned
          ? t.copyWith(pinnedAt: DateTime.now(), archived: false)
          : t.copyWith(clearPinnedAt: true));

  /// Archive or unarchive a chat for myself. Archiving unpins, as on the server.
  Future<void> setArchived(String addressingId, bool archived) =>
      _setState(addressingId, {'archived': archived}, (t) => archived
          ? t.copyWith(archived: true, clearPinnedAt: true)
          : t.copyWith(archived: false));

  Future<void> _setState(
    String addressingId,
    Map<String, bool> change,
    MessageThread Function(MessageThread) optimistic,
  ) async {
    final before = state.asData?.value.where((t) => t.addressingId == addressingId).firstOrNull;
    _updateThread(addressingId, optimistic);
    try {
      await ref.read(apiClientProvider).dio.patch('/messages/threads/$addressingId/state', data: change);
    } catch (_) {
      // Restore only what this change touched; a message may have landed on the row meanwhile.
      if (before != null) {
        _updateThread(
          addressingId,
          (t) => t.copyWith(
            pinnedAt: before.pinnedAt,
            clearPinnedAt: before.pinnedAt == null,
            archived: before.archived,
          ),
        );
      }
      rethrow;
    }
  }

  /// Mute or unmute a chat for myself — optimistic, rolled back if the server refuses.
  Future<void> setMuted(String addressingId, bool muted) async {
    final before = state.asData?.value
        .where((t) => t.addressingId == addressingId)
        .firstOrNull
        ?.muted;
    _updateThread(addressingId, (t) => t.copyWith(muted: muted));
    try {
      await ref.read(apiClientProvider).dio.patch(
        '/messages/threads/$addressingId/mute',
        data: {'muted': muted},
      );
    } catch (_) {
      if (before != null) _updateThread(addressingId, (t) => t.copyWith(muted: before));
      rethrow;
    }
  }

  void _onTyping(TypingEvent event) {
    _setThreadTyping(event.conversationId, event.active);
    _typingTimers.remove(event.conversationId)?.cancel();
    if (event.active) {
      _typingTimers[event.conversationId] = Timer(
        const Duration(seconds: 4),
        () => _setThreadTyping(event.conversationId, false),
      );
    }
  }

  void _setThreadTyping(String conversationId, bool typing) {
    final current = state.asData?.value;
    if (current == null) return;
    final idx = current.indexWhere((t) => t.addressingId == conversationId);
    if (idx == -1 || current[idx].partnerTyping == typing) return;
    final updated = List<MessageThread>.from(current);
    updated[idx] = updated[idx].copyWith(partnerTyping: typing);
    state = AsyncData(updated);
  }

  /// Add a freshly started thread (e.g. a new staff conversation) to the top of the inbox,
  /// if it isn't already loaded — so it shows up without a full refetch.
  void upsertThread(MessageThread thread) {
    if (thread.isStaffThread && thread.latestMessage == null) return;
    final current = state.asData?.value;
    if (current == null) return;
    if (current.any((t) => t.conversationId == thread.conversationId)) return;
    state = AsyncData([thread, ...current]);
  }
}
