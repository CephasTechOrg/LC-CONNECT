part of '../screens/chat_screen.dart';

/// Replying to a message: the composer's quote, keeping quotes current, and jumping to the
/// original when a quote is tapped (protocol 5).
mixin _ChatReplyLogic on _ChatScreenStateBase {
  // Implemented by _ChatScreenLogic, which is mixed in after this one.
  Future<void> loadOlder();

  /// How many older pages a quote tap may load while looking for its original — 250 messages.
  static const _maxJumpPages = 5;

  bool get canReply => rt.supportsProtocol(kReplyProtocolVersion);

  void startReply(ChatMessage message) {
    if (!canReply || message.deleted || message.id.startsWith('local:')) return;
    HapticFeedback.selectionClick();
    setState(() => replyingTo = message);
  }

  void cancelReply() => setState(() => replyingTo = null);

  /// The name a quote shows for [userId]: "You", a group member, or the DM partner.
  String quoteSenderName(String userId) {
    if (userId == currentUserId) return 'You';
    if (isGroup) return senders()[userId]?.name ?? 'Member';
    return widget.thread?.partner?.displayName ?? 'Them';
  }

  /// Bring every loaded quote of [messageId] up to date after it was edited or deleted.
  /// Call inside `setState`.
  void refreshQuotesOf(String messageId, {String? snippet, bool deleted = false}) {
    for (var i = 0; i < messages.length; i++) {
      final quote = messages[i].replyTo;
      if (quote == null || quote.id != messageId) continue;
      messages[i] = messages[i].copyWith(
        replyTo: deleted
            ? quote.copyWith(snippet: '', deleted: true)
            : quote.copyWith(snippet: snippet, edited: true),
      );
    }
  }

  /// Scroll to [messageId] and highlight it briefly, loading older pages if it is not loaded yet.
  Future<void> jumpToMessage(String messageId) async {
    var pages = 0;
    while (!messages.any((m) => m.id == messageId) && hasMore && pages < _maxJumpPages) {
      pages++;
      await loadOlder();
      if (disposed || !mounted) return;
    }
    if (!messages.any((m) => m.id == messageId)) {
      _jumpFailed();
      return;
    }
    setState(() => highlightedId = messageId);
    highlightTimer?.cancel();
    highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!disposed && mounted) setState(() => highlightedId = null);
    });
    // The list builds lazily, so the bubble may not exist yet: estimate its offset first, then
    // let `ensureVisible` place it exactly once it is built.
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (disposed || !mounted) return;
      final ctx = bubbleKeys[messageId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 300));
        return;
      }
      if (scrollController.hasClients) {
        final index = messages.indexWhere((m) => m.id == messageId);
        final fraction = messages.length <= 1 ? 0.0 : index / (messages.length - 1);
        scrollController.jumpTo(scrollController.position.maxScrollExtent * fraction);
      }
    }
  }

  void _jumpFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't find the original message."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
