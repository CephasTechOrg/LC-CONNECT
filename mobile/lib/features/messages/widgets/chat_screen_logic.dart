part of '../screens/chat_screen.dart';

mixin _ChatScreenLogic on _ChatScreenStateBase, _ChatDraftLogic, _ChatSendLogic {
  Future<void> loadInitial() async {
    if (!validThread) return;
    final cached = await ref.read(chatMessageCacheProvider).load(widget.matchId);
    if (mounted && cached != null && cached.isNotEmpty) {
      setState(() {
        absorb(cached);
        loading = false;
      });
      scrollToBottom(jump: true, force: true);
    }
    try {
      final resp = await ref
          .read(apiClientProvider)
          .dio
          .get('/messages/threads/${widget.matchId}', queryParameters: {'limit': _ChatScreenStateBase.pageSize});
      if (disposed || !mounted) return;
      final page = parsePage(resp.data as List);
      setState(() {
        absorb(page);
        hasMore = page.length >= _ChatScreenStateBase.pageSize;
        loading = false;
        loadError = null;
      });
      scrollToBottom(jump: true, force: true);
      sendRead();
      scheduleCacheSave();
    } catch (e) {
      if (disposed || !mounted) return;
      setState(() {
        loading = false;
        if (messages.isEmpty) {
          loadError = apiErrorMessage(
            e,
            fallback: 'Could not load this conversation. Check your connection and try again.',
          );
        }
      });
    }
  }

  void retryLoadInitial() {
    setState(() {
      loading = true;
      loadError = null;
    });
    loadInitial();
  }

  Future<void> loadOlder() async {
    if (loadingOlder || !hasMore || messages.isEmpty) return;
    final oldest = messages.first;
    if (oldest.id.startsWith('local:')) return;
    loadingOlder = true;
    try {
      final resp = await ref.read(apiClientProvider).dio.get(
        '/messages/threads/${widget.matchId}',
        queryParameters: {
          'before_created_at': oldest.createdAt.toUtc().toIso8601String(),
          'before_id': oldest.id,
          'limit': _ChatScreenStateBase.pageSize,
        },
      );
      if (disposed || !mounted) return;
      final older = parsePage(resp.data as List);
      setState(() {
        absorb(older);
        hasMore = older.length >= _ChatScreenStateBase.pageSize;
      });
    } catch (_) {
    } finally {
      loadingOlder = false;
    }
  }

  Future<void> syncAfterReconnect() async {
    if (disposed || !mounted) return;
    if (!validThread) return;
    rt.subscribe(widget.matchId);
    final newest = newestServerMessage();
    if (newest == null) return loadInitial();
    try {
      var cursor = newest;
      var totalMissed = 0;
      while (mounted) {
        final resp = await ref.read(apiClientProvider).dio.get(
          '/messages/threads/${widget.matchId}/sync',
          queryParameters: {
            'after_created_at': cursor.createdAt.toUtc().toIso8601String(),
            'after_id': cursor.id,
            'limit': 100,
          },
        );
        if (disposed || !mounted) return;
        final missed = parseAscending(resp.data as List);
        if (missed.isEmpty) break;
        setState(() => absorb(missed));
        totalMissed += missed.length;
        if (missed.length < 100) break;
        cursor = missed.last;
      }
      if (totalMissed > 0) {
        if (isNearBottom) {
          scrollToBottom();
        } else {
          setState(() => newWhileAway += totalMissed);
        }
        scheduleCacheSave();
      }
    } catch (_) {}
  }

  ChatMessage? newestServerMessage() {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (!messages[i].id.startsWith('local:')) return messages[i];
    }
    return null;
  }

  List<ChatMessage> parsePage(List<dynamic> raw) => parseAscending(raw);

  List<ChatMessage> parseAscending(List<dynamic> raw) {
    final list = raw.map((j) => ChatMessage.fromJson(j as Map<String, dynamic>)).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  void absorb(List<ChatMessage> serverMessages) {
    final incomingClientIds = <String>{
      for (final m in serverMessages)
        if (m.clientMessageId != null) m.clientMessageId!,
    };
    final byId = <String, ChatMessage>{};
    for (final m in messages) {
      if (m.id.startsWith('local:') &&
          m.clientMessageId != null &&
          incomingClientIds.contains(m.clientMessageId)) {
        continue;
      }
      byId[m.id] = m;
    }
    for (final m in serverMessages) {
      byId[m.id] = m;
      seenServerIds.add(m.id);
    }
    final merged = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messages
      ..clear()
      ..addAll(merged);
    final liveIds = merged.map((m) => m.id).toSet();
    seenServerIds.removeWhere((id) => !liveIds.contains(id));
  }

  @override
  void scheduleCacheSave() {
    cacheSaveTimer?.cancel();
    cacheSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || !validThread) return;
      ref.read(chatMessageCacheProvider).save(widget.matchId, messages);
    });
  }

  @override
  bool get isNearBottom {
    if (!scrollController.hasClients) return true;
    final pos = scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= _kScrollBottomThreshold;
  }

  void onEvent(InboundEvent event) {
    if (disposed || !mounted) return;
    switch (event) {
      case MessageCreated(:final conversationId, :final message) when conversationId == widget.matchId:
        mergeIncoming(ChatMessage.fromJson(message));
        sendRead();
      case MessageAck(:final message) when message['conversation_id'] == widget.matchId:
        reconcileAck(ChatMessage.fromJson(message));
      case TypingEvent(:final conversationId, :final userId, :final active) when conversationId == widget.matchId:
        setPartnerTyping(active, userId);
      case ReadReceipt(:final conversationId, :final throughMessageId)
          when conversationId == widget.matchId:
        markMineReadThrough(throughMessageId);
      case DeliveryReceipt(:final conversationId, :final throughMessageId)
          when conversationId == widget.matchId:
        markMineDeliveredThrough(throughMessageId);
      case MessageDeleted(:final conversationId, :final messageId) when conversationId == widget.matchId:
        markDeleted(messageId);
      case WsError(:final code, :final message, :final requestId):
        handleWsError(code, message, requestId: requestId);
      default:
        break;
    }
  }

  void markDeleted(String messageId) {
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1 || messages[idx].deleted) return;
    setState(() => messages[idx] = messages[idx].copyWith(deleted: true));
  }

  Future<void> deleteMessage(ChatMessage msg) async {
    markDeleted(msg.id);
    try {
      await ref.read(apiClientProvider).dio.delete('/messages/${msg.id}');
    } catch (_) {
      if (disposed || !mounted) return;
      final idx = messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) setState(() => messages[idx] = messages[idx].copyWith(deleted: false));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete the message', style: GoogleFonts.dmSans(color: Colors.white)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void setPartnerTyping(bool active, [String? userId]) {
    typingResetTimer?.cancel();
    setState(() {
      partnerTyping = active;
      typingUserId = active ? userId : null;
    });
    if (active) {
      typingResetTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => partnerTyping = false);
      });
    }
  }

  String typingName(MessagePartner? partner) {
    if (isGroup) return senders()[typingUserId]?.name ?? 'Someone';
    return partner?.displayName ?? 'Your match';
  }

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

  void onUserTyping() {
    // The composer's `onChanged` discards the text, and threading a second callback down through
    // _ChatScreenBody and _InputBar to recover it would be three signatures wide. The screen owns
    // the controller, so it reads the text here instead. Debounced inside [onDraftChanged].
    onDraftChanged(inputController.text);
    final now = DateTime.now();
    if (now.difference(lastTypingSent).inMilliseconds > 1500) {
      lastTypingSent = now;
      rt.sendTyping(widget.matchId, active: true);
    }
    typingStopTimer?.cancel();
    typingStopTimer = Timer(const Duration(seconds: 3), () => rt.sendTyping(widget.matchId, active: false));
  }

  void onScroll() {
    final nearBottom = isNearBottom;
    if (nearBottom != !awayFromBottom) {
      setState(() {
        awayFromBottom = !nearBottom;
        if (nearBottom) newWhileAway = 0;
      });
    }
    if (scrollController.position.pixels <= 80 && !loadingOlder && hasMore) {
      loadOlder();
    }
  }

  void scrollToBottomTap() {
    setState(() {
      awayFromBottom = false;
      newWhileAway = 0;
    });
    scrollToBottom(force: true);
  }

  @override
  void scrollToBottom({bool jump = false, bool force = false}) {
    if (!force && awayFromBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      final target = scrollController.position.maxScrollExtent;
      if (jump) {
        scrollController.jumpTo(target);
      } else {
        scrollController.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      }
    });
  }
}
