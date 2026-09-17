part of '../screens/chat_screen.dart';

/// The send path: optimistic bubble → WebSocket → REST escalation → reconcile.
///
/// Sending used to be WebSocket-only with a flat 8s "failed" timer. That timer was shorter than
/// the client's own reconnect backoff (up to 30s), so a message queued across a reconnect went
/// red and then quietly delivered — the "sometimes it fails, sometimes it takes a while" report.
/// Here a timeout means *escalate*, not *fail*: the REST route is idempotent on
/// `client_message_id`, so the two paths can race without ever duplicating a message.
mixin _ChatSendLogic on _ChatScreenStateBase {
  // Implemented by _ChatScreenLogic, which is mixed in after this one.
  void scheduleCacheSave();
  void scrollToBottom({bool jump, bool force});
  bool get isNearBottom;

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
    sendStartedAt[clientId] = DateTime.now();
    dispatchSend(clientId, text);
    scrollToBottom(force: true);
    scheduleCacheSave();
  }

  void dispatchSend(String clientId, String body) {
    sendStartedAt.putIfAbsent(clientId, DateTime.now);
    // Captured before the send: `sendMessage` queues to the outbox when the socket is not ready,
    // and a queued frame goes nowhere until the next `auth.ok`.
    final socketReady = rt.status.value == RealtimeStatus.ready;
    final accepted = rt.sendMessage(
      conversationId: widget.matchId,
      clientMessageId: clientId,
      body: body,
    );
    if (!accepted) {
      // The offline outbox is full — the only case where we fail immediately, because we have
      // nowhere to hold the message and the user needs to know it did not go.
      markSendFailed(clientId);
      if (mounted) _showOutboxFullSnack(context);
      return;
    }

    if (!socketReady) {
      // The socket is knowably not ready, so waiting out the ack timer would buy nothing — the
      // frame is sitting in the outbox waiting for a handshake that may take seconds (the WS
      // connect timeout is 30s for cold starts). Racing HTTP now is safe *because* the server is
      // idempotent on `client_message_id`: whichever arrives second returns the same row with
      // `duplicate: true`, and `escalateToRest` cancels the pending WS send on success.
      //
      // This is what removes a fixed multi-second stall from the first message after every
      // app resume — the socket is torn down on background by design.
      unawaited(escalateToRest(clientId, body));
      return;
    }
    armAckTimer(clientId, body);
  }

  /// How long to wait for an ack before trying HTTP.
  ///
  /// A healthy ack is tens of milliseconds, so a flat 6s meant a genuinely lost frame stalled far
  /// longer than the evidence warranted. Three times the slowest of the last few acks adapts to
  /// the actual connection — a good one escalates fast, a slow-but-working one is not cut off
  /// mid-flight — clamped to [_ChatScreenStateBase.ackTimeout] so it can never exceed the old
  /// behaviour.
  Duration ackTimeoutFor() {
    if (ackLatencies.isEmpty) return _ChatScreenStateBase.ackTimeout;
    var worst = Duration.zero;
    for (final sample in ackLatencies) {
      if (sample > worst) worst = sample;
    }
    final scaled = worst * 3;
    if (scaled < _ChatScreenStateBase.minAckTimeout) {
      return _ChatScreenStateBase.minAckTimeout;
    }
    return scaled > _ChatScreenStateBase.ackTimeout ? _ChatScreenStateBase.ackTimeout : scaled;
  }

  /// Records an observed ack round-trip, keeping only the recent window.
  void recordAckLatency(Duration latency) {
    if (latency <= Duration.zero) return;
    ackLatencies.add(latency);
    while (ackLatencies.length > _ChatScreenStateBase.ackSampleSize) {
      ackLatencies.removeAt(0);
    }
  }

  /// Not a failure timer: when it fires we try the other road.
  void armAckTimer(String clientId, String body) {
    sendTimers[clientId]?.cancel();
    sendTimers[clientId] = Timer(ackTimeoutFor(), () {
      if (!mounted || !isStillSending(clientId)) return;
      unawaited(escalateToRest(clientId, body));
    });
  }

  bool isStillSending(String clientId) {
    final idx = messages.indexWhere((m) => m.clientMessageId == clientId);
    return idx != -1 && messages[idx].status == MessageStatus.sending;
  }

  bool pastDeadline(String clientId) {
    final started = sendStartedAt[clientId];
    if (started == null) return false;
    return DateTime.now().difference(started) >= _ChatScreenStateBase.sendDeadline;
  }

  /// Deliver over HTTP when the socket has not acked in time. Idempotent on the server via
  /// `client_message_id`, so this cannot double-post even if the original frame lands later.
  Future<void> escalateToRest(String clientId, String body) async {
    try {
      final resp = await ref.read(apiClientProvider).dio.post(
            '/messages/threads/${widget.matchId}',
            data: {'body': body, 'client_message_id': clientId},
          );
      if (disposed || !mounted) return;
      // Delivered — stop the socket from retrying the same message on reconnect.
      rt.cancelPendingSend(clientId);
      reconcileAck(ChatMessage.fromJson(Map<String, dynamic>.from(resp.data as Map)));
    } catch (e) {
      if (disposed || !mounted) return;
      final status = apiStatusCode(e);
      if (status == 429) {
        markSendFailed(clientId);
        showSendSnack('Sending too fast — please wait a moment.');
        return;
      }
      if (status != null && status >= 400 && status < 500) {
        // A real rejection (no longer a member, blocked, thread closed) — retrying won't help.
        markSendFailed(clientId);
        showSendSnack(apiErrorMessage(e, fallback: 'Could not send that message.'));
        return;
      }
      // Network error or a cold-started server. The frame may still be queued on the socket,
      // so keep the bubble in `sending` and try again — this preserves "compose offline, it
      // delivers on reconnect" rather than turning a slow start into a false failure.
      if (pastDeadline(clientId)) {
        markSendFailed(clientId);
        return;
      }
      sendTimers[clientId]?.cancel();
      sendTimers[clientId] = Timer(_ChatScreenStateBase.restRetryDelay, () {
        if (!mounted || !isStillSending(clientId)) return;
        unawaited(escalateToRest(clientId, body));
      });
    }
  }

  void markSendFailed(String clientId) {
    sendTimers.remove(clientId)?.cancel();
    if (disposed || !mounted) return;
    final idx = messages.indexWhere((m) => m.clientMessageId == clientId);
    if (idx == -1) return;
    setState(() => messages[idx] = messages[idx].copyWith(status: MessageStatus.failed));
    scheduleCacheSave();
  }

  void showSendSnack(String text) {
    if (disposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: GoogleFonts.dmSans(color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void retry(ChatMessage failed) {
    final cid = failed.clientMessageId;
    if (cid == null) return;
    final idx = messages.indexWhere((m) => m.clientMessageId == cid);
    if (idx == -1) return;
    setState(() => messages[idx] = messages[idx].copyWith(status: MessageStatus.sending));
    sendStartedAt[cid] = DateTime.now(); // a manual retry gets a fresh deadline
    dispatchSend(cid, failed.body);
  }

  void reconcileAck(ChatMessage server) {
    final cid = server.clientMessageId;
    final idx = cid == null ? -1 : messages.indexWhere((m) => m.clientMessageId == cid);
    sendTimers.remove(cid)?.cancel();
    final startedAt = sendStartedAt.remove(cid);
    // Feeds the adaptive ack window. Only a timer that was still pending counts as a clean
    // round-trip — a reconcile arriving after escalation says nothing about socket latency.
    if (startedAt != null) recordAckLatency(DateTime.now().difference(startedAt));
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

  void mergeIncoming(ChatMessage msg) {
    if (seenServerIds.contains(msg.id)) return;
    final cid = msg.clientMessageId;
    if (cid != null && messages.any((m) => m.clientMessageId == cid)) {
      // Our own message coming back over the conversation channel. Reconcile rather than drop
      // it: if the ack was missed (or REST won the race) the bubble would otherwise sit on
      // "sending" forever. Senders receive their own message.created, so this is a live path.
      reconcileAck(msg);
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

  /// Fail only the message the server actually rejected.
  ///
  /// Previously any `rate_limited`/`forbidden` frame failed *every* bubble still sending — and
  /// the subscribe limiter emits `rate_limited` too, so flicking quickly between chats could
  /// redden messages that were fine. Errors the server cannot attribute to a specific send are
  /// surfaced as a message, not as a failure.
  void handleWsError(String code, String message, {String? requestId}) {
    if (code != 'rate_limited' && code != 'forbidden') return;
    final clientId = requestId == null ? null : rt.clientMessageIdForRequest(requestId);
    final text = code == 'rate_limited' ? 'Sending too fast — please wait a moment.' : message;
    if (clientId == null) {
      showSendSnack(text);
      return;
    }
    markSendFailed(clientId);
    showSendSnack(text);
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
}
