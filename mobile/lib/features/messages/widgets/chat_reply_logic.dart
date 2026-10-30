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
  /// Used for a reply's quote, a search result, and (unhighlighted, near the top) the first
  /// unread message.
  Future<void> jumpToMessage(
    String messageId, {
    bool highlight = true,
    double alignment = 0.3,
    String notFound = "Couldn't find the original message.",
  }) async {
    var pages = 0;
    while (!messages.any((m) => m.id == messageId) && hasMore && pages < _maxJumpPages) {
      pages++;
      await loadOlder();
      if (disposed || !mounted) return;
    }
    if (!messages.any((m) => m.id == messageId)) {
      _jumpFailed(notFound);
      return;
    }
    if (highlight) {
      setState(() => highlightedId = messageId);
      highlightTimer?.cancel();
      highlightTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!disposed && mounted) setState(() => highlightedId = null);
      });
    }
    // The list builds lazily, so the bubble may not exist yet: estimate its offset first, then
    // let `ensureVisible` place it exactly once it is built.
    for (var attempt = 0; attempt < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (disposed || !mounted) return;
      final ctx = bubbleKeys[messageId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: alignment, duration: const Duration(milliseconds: 300));
        return;
      }
      if (scrollController.hasClients) {
        final index = messages.indexWhere((m) => m.id == messageId);
        final fraction = messages.length <= 1 ? 0.0 : index / (messages.length - 1);
        scrollController.jumpTo(scrollController.position.maxScrollExtent * fraction);
      }
    }
  }

  void _jumpFailed(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  /// Where a chat opens: at the message a search result named, else at the first unread message
  /// under a "New messages" divider (as in WhatsApp), else at the bottom. Runs once, after the
  /// first page from the server.
  Future<void> openAtTarget() async {
    if (openedAtTarget) return;
    openedAtTarget = true;
    final target = widget.jumpTo;
    if (target != null) {
      await jumpToMessage(target, notFound: "Couldn't find that message.");
      return;
    }
    final firstUnread = firstUnreadId(messages, mine: currentUserId, unread: unreadOnOpen);
    if (firstUnread == null) return;
    setState(() => unreadDividerBefore = firstUnread);
    await jumpToMessage(firstUnread, highlight: false, alignment: 0.05);
  }
}

/// The oldest of the last [unread] messages from other people — where the "New messages" divider
/// goes. Null when nothing is unread or those messages are not loaded.
String? firstUnreadId(List<ChatMessage> messages, {required String mine, required int unread}) {
  if (unread <= 0) return null;
  final theirs = [for (final m in messages) if (m.senderId != mine && !m.deleted) m];
  if (theirs.length < unread) return theirs.isEmpty ? null : theirs.first.id;
  return theirs[theirs.length - unread].id;
}
