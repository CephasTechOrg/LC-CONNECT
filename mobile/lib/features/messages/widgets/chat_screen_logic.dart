part of '../screens/chat_screen.dart';

mixin _ChatScreenLogic on _ChatScreenStateBase {
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
      if (!mounted) return;
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
      if (!mounted) return;
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
      if (!mounted) return;
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
        if (!mounted) return;
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

  void scheduleCacheSave() {
    cacheSaveTimer?.cancel();
    cacheSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || !validThread) return;
      ref.read(chatMessageCacheProvider).save(widget.matchId, messages);
    });
  }

  bool get isNearBottom {
    if (!scrollController.hasClients) return true;
    final pos = scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= _kScrollBottomThreshold;
  }

  void onEvent(InboundEvent event) {
    if (!mounted) return;
    switch (event) {
      case MessageCreated(:final conversationId, :final message) when conversationId == widget.matchId:
        mergeIncoming(ChatMessage.fromJson(message));
        sendRead();
      case MessageAck(:final message) when message['conversation_id'] == widget.matchId:
        reconcileAck(ChatMessage.fromJson(message));
      case TypingEvent(:final conversationId, :final userId, :final active) when conversationId == widget.matchId:
        setPartnerTyping(active, userId);
      case ReadReceipt(:final conversationId) when conversationId == widget.matchId:
        markMineRead();
      case MessageDeleted(:final conversationId, :final messageId) when conversationId == widget.matchId:
        markDeleted(messageId);
      case WsError(:final code, :final message):
        handleWsError(code, message);
      default:
        break;
    }
  }

  void handleWsError(String code, String message) {
    if (code != 'rate_limited' && code != 'forbidden') return;
    var failed = false;
    setState(() {
      for (var i = 0; i < messages.length; i++) {
        if (messages[i].status == MessageStatus.sending) {
          messages[i] = messages[i].copyWith(status: MessageStatus.failed);
          failed = true;
        }
      }
    });
    if (!failed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code == 'rate_limited' ? 'Sending too fast — please wait a moment.' : message,
          style: GoogleFonts.dmSans(color: Colors.white),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
      if (!mounted) return;
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

  void mergeIncoming(ChatMessage msg) {
    if (seenServerIds.contains(msg.id)) return;
    if (msg.clientMessageId != null &&
        messages.any((m) => m.clientMessageId == msg.clientMessageId)) {
      seenServerIds.add(msg.id);
      return;
    }
    setState(() {
      seenServerIds.add(msg.id);
      messages.add(msg);
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    final isMine = msg.senderId == currentUserId;
    if (isMine || isNearBottom) {
      scrollToBottom(force: true);
    } else {
      setState(() => newWhileAway++);
    }
    scheduleCacheSave();
  }

  void reconcileAck(ChatMessage server) {
    final cid = server.clientMessageId;
    final idx = cid == null ? -1 : messages.indexWhere((m) => m.clientMessageId == cid);
    sendTimers.remove(cid)?.cancel();
    setState(() {
      seenServerIds.add(server.id);
      if (idx == -1) {
        if (!messages.any((m) => m.id == server.id)) messages.add(server);
      } else {
        messages[idx] = server.copyWith(status: MessageStatus.sent);
      }
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    scheduleCacheSave();
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

  void markMineRead() {
    setState(() {
      for (var i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (m.senderId == currentUserId && m.readAt == null) {
          messages[i] = m.copyWith(readAt: DateTime.now());
        }
      }
    });
  }

  void send() {
    if (!validThread) return;
    final text = inputController.text.trim();
    if (text.isEmpty) return;
    inputController.clear();
    typingStopTimer?.cancel();
    rt.sendTyping(widget.matchId, active: false);
    final clientId = uuidV4();
    final optimistic = ChatMessage(
      id: 'local:$clientId',
      matchId: widget.matchId,
      senderId: currentUserId,
      clientMessageId: clientId,
      body: text,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    setState(() => messages.add(optimistic));
    dispatchSend(clientId, text);
    scrollToBottom(force: true);
    scheduleCacheSave();
  }

  void dispatchSend(String clientId, String body) {
    final accepted = rt.sendMessage(
      conversationId: widget.matchId,
      clientMessageId: clientId,
      body: body,
    );
    if (!accepted) {
      sendTimers.remove(clientId)?.cancel();
      if (!mounted) return;
      final idx = messages.indexWhere((m) => m.clientMessageId == clientId);
      if (idx != -1) {
        setState(() => messages[idx] = messages[idx].copyWith(status: MessageStatus.failed));
      }
      scheduleCacheSave();
      _showOutboxFullSnack(context);
      return;
    }
    sendTimers[clientId]?.cancel();
    sendTimers[clientId] = Timer(_ChatScreenStateBase.sendTimeout, () {
      if (!mounted) return;
      final idx = messages.indexWhere((m) => m.clientMessageId == clientId);
      if (idx != -1 && messages[idx].status == MessageStatus.sending) {
        setState(() => messages[idx] = messages[idx].copyWith(status: MessageStatus.failed));
      }
    });
  }

  void retry(ChatMessage failed) {
    final cid = failed.clientMessageId;
    if (cid == null) return;
    final idx = messages.indexWhere((m) => m.clientMessageId == cid);
    if (idx == -1) return;
    setState(() => messages[idx] = messages[idx].copyWith(status: MessageStatus.sending));
    dispatchSend(cid, failed.body);
  }

  void onUserTyping() {
    final now = DateTime.now();
    if (now.difference(lastTypingSent).inMilliseconds > 1500) {
      lastTypingSent = now;
      rt.sendTyping(widget.matchId, active: true);
    }
    typingStopTimer?.cancel();
    typingStopTimer = Timer(const Duration(seconds: 3), () => rt.sendTyping(widget.matchId, active: false));
  }

  void sendRead() {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (!m.id.startsWith('local:')) {
        rt.markRead(widget.matchId, m.id);
        return;
      }
    }
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
