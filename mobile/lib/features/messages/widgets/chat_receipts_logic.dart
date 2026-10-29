part of '../screens/chat_screen.dart';

/// Read and delivery receipts for my own messages. Split out of `chat_screen_logic.dart`.
mixin _ChatReceiptLogic on _ChatScreenStateBase {
  /// Mark my messages up to and including [throughMessageId] as read.
  void markMineReadThrough(String throughMessageId) =>
      _advanceMine(throughMessageId, (m, at) => m.copyWith(readAt: at, delivered: true));

  /// Mark my messages up to and including [throughMessageId] as delivered.
  void markMineDeliveredThrough(String throughMessageId) =>
      _advanceMine(throughMessageId, (m, at) => m.copyWith(delivered: true));

  /// Apply [stamp] to every message of mine at or before [throughMessageId].
  ///
  /// The receipt is a *boundary*, and this used to ignore it and flip every unread message of
  /// mine instead. That was invisible while there was one thing to flip: with a single read tick,
  /// "all" and "up to here" look the same the moment the partner is caught up — which they
  /// usually are. With delivered and read as separate states it becomes visibly wrong, and wrong
  /// in the direction that matters: it claims someone read a message they have not reached.
  ///
  /// Ordered by `(createdAt, id)` rather than list position: the list is sorted, but an
  /// optimistic row sits at the tail with a client-side timestamp, and position alone would mark
  /// it read by anything that arrived after it.
  ///
  /// A boundary naming a message that is not loaded (paged out, or newer than this client's tail)
  /// is ignored — the next page load carries the correct state.
  void _advanceMine(
    String throughMessageId,
    ChatMessage Function(ChatMessage message, DateTime at) stamp,
  ) {
    final boundary = messages.where((m) => m.id == throughMessageId).firstOrNull;
    if (boundary == null) return;
    final at = DateTime.now();
    var changed = false;
    final updated = [
      for (final m in messages)
        if (m.senderId == currentUserId && !_isAfter(m, boundary))
          _stampIfNeeded(m, stamp, at, () => changed = true)
        else
          m,
    ];
    if (!changed) return;
    setState(() {
      messages
        ..clear()
        ..addAll(updated);
    });
  }

  /// Keeps [_advanceMine] from rebuilding when a receipt is re-sent — which the client does after
  /// every reconnect, and the socket is torn down on every app background.
  ChatMessage _stampIfNeeded(
    ChatMessage message,
    ChatMessage Function(ChatMessage, DateTime) stamp,
    DateTime at,
    void Function() onChanged,
  ) {
    final next = stamp(message, at);
    if (next.readAt == message.readAt && next.delivered == message.delivered) return message;
    onChanged();
    return next;
  }

  /// `(createdAt, id)` ordering — the same key the server's boundary comparison uses, so the two
  /// sides cannot disagree about what "up to here" includes.
  bool _isAfter(ChatMessage a, ChatMessage b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime > 0 : a.id.compareTo(b.id) > 0;
  }
}
