import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/messages_provider.dart';

part '../widgets/chat_header.dart';
part '../widgets/chat_message_list.dart';
part '../widgets/chat_bubble.dart';
part '../widgets/chat_input.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String matchId;
  final MessageThread? thread;

  const ChatScreen({super.key, required this.matchId, this.thread});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _pageSize = 50;
  static const _sendTimeout = Duration(seconds: 8);

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = []; // ascending (oldest → newest)
  final _seenServerIds = <String>{};
  final _sendTimers = <String, Timer>{}; // clientMessageId → fail-after timer

  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _partnerTyping = false;
  String _currentUserId = '';
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<InboundEvent>? _eventsSub;
  StreamSubscription<void>? _reconnectSub;
  Timer? _typingResetTimer;
  Timer? _typingStopTimer;

  RealtimeClient get _rt => ref.read(realtimeClientProvider);

  @override
  void initState() {
    super.initState();
    _currentUserId = ref.read(authNotifierProvider).asData?.value?.id ?? '';
    _rt.subscribe(widget.matchId);
    _eventsSub = _rt.events.listen(_onEvent);
    _reconnectSub = _rt.reconnected.listen((_) => _syncAfterReconnect());
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _rt.unsubscribe(widget.matchId);
    _eventsSub?.cancel();
    _reconnectSub?.cancel();
    _typingResetTimer?.cancel();
    _typingStopTimer?.cancel();
    for (final t in _sendTimers.values) {
      t.cancel();
    }
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── history (paginated REST) ──────────────────────────────────────

  Future<void> _loadInitial() async {
    try {
      final resp = await ref
          .read(apiClientProvider)
          .dio
          .get('/messages/threads/${widget.matchId}', queryParameters: {'limit': _pageSize});
      if (!mounted) return;
      final page = _parsePage(resp.data as List); // newest-first → ascending
      setState(() {
        _absorb(page); // merge — preserve any live messages that arrived during the load
        _hasMore = page.length >= _pageSize;
        _loading = false;
      });
      _scrollToBottom(jump: true);
      _sendRead();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    final oldest = _messages.first;
    if (oldest.id.startsWith('local:')) return; // no server cursor yet
    _loadingOlder = true;
    try {
      final resp = await ref.read(apiClientProvider).dio.get(
        '/messages/threads/${widget.matchId}',
        queryParameters: {
          'before_created_at': oldest.createdAt.toUtc().toIso8601String(),
          'before_id': oldest.id,
          'limit': _pageSize,
        },
      );
      if (!mounted) return;
      final older = _parsePage(resp.data as List);
      setState(() {
        _absorb(older);
        _hasMore = older.length >= _pageSize;
      });
    } catch (_) {
      // keep _hasMore; user can retry by scrolling
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _syncAfterReconnect() async {
    _rt.subscribe(widget.matchId);
    final newest = _newestServerMessage();
    if (newest == null) return _loadInitial();
    try {
      final resp = await ref.read(apiClientProvider).dio.get(
        '/messages/threads/${widget.matchId}/sync',
        queryParameters: {
          'after_created_at': newest.createdAt.toUtc().toIso8601String(),
          'after_id': newest.id,
          'limit': 100,
        },
      );
      if (!mounted) return;
      final missed = _parseAscending(resp.data as List);
      if (missed.isNotEmpty) {
        setState(() => _absorb(missed));
        _scrollToBottom();
      }
    } catch (_) {}
  }

  ChatMessage? _newestServerMessage() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (!_messages[i].id.startsWith('local:')) return _messages[i];
    }
    return null;
  }

  List<ChatMessage> _parsePage(List<dynamic> raw) => _parseAscending(raw);

  List<ChatMessage> _parseAscending(List<dynamic> raw) {
    final list = raw.map((j) => ChatMessage.fromJson(j as Map<String, dynamic>)).toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Merge server messages into the list by id — never clobbers live messages that
  /// arrived during a load, and drops an optimistic row once its server row appears.
  /// (Call inside setState.)
  void _absorb(List<ChatMessage> serverMessages) {
    final incomingClientIds = <String>{
      for (final m in serverMessages)
        if (m.clientMessageId != null) m.clientMessageId!,
    };
    final byId = <String, ChatMessage>{};
    for (final m in _messages) {
      if (m.id.startsWith('local:') &&
          m.clientMessageId != null &&
          incomingClientIds.contains(m.clientMessageId)) {
        continue; // superseded by its server version below
      }
      byId[m.id] = m;
    }
    for (final m in serverMessages) {
      byId[m.id] = m;
      _seenServerIds.add(m.id);
    }
    final merged = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    _messages
      ..clear()
      ..addAll(merged);
  }

  // ── live events ───────────────────────────────────────────────────

  void _onEvent(InboundEvent event) {
    if (!mounted) return;
    switch (event) {
      case MessageCreated(:final conversationId, :final message) when conversationId == widget.matchId:
        _mergeIncoming(ChatMessage.fromJson(message));
        _sendRead();
      case MessageAck(:final message) when message['conversation_id'] == widget.matchId:
        _reconcileAck(ChatMessage.fromJson(message));
      case TypingEvent(:final conversationId, :final active) when conversationId == widget.matchId:
        _setPartnerTyping(active);
      case ReadReceipt(:final conversationId) when conversationId == widget.matchId:
        _markMineRead();
      default:
        break;
    }
  }

  void _mergeIncoming(ChatMessage msg) {
    if (_seenServerIds.contains(msg.id)) {
      if (kDebugMode) debugPrint('chat: skip (seen) ${msg.id}');
      return;
    }
    // Our own message echoed back — already reconciled via ack.
    if (msg.clientMessageId != null &&
        _messages.any((m) => m.clientMessageId == msg.clientMessageId)) {
      if (kDebugMode) debugPrint('chat: skip (dedup client ${msg.clientMessageId}) ${msg.id}');
      _seenServerIds.add(msg.id);
      return;
    }
    if (kDebugMode) debugPrint('chat: merged ${msg.id} from ${msg.senderId}');
    setState(() {
      _seenServerIds.add(msg.id);
      _messages.add(msg);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    _scrollToBottom();
  }

  void _reconcileAck(ChatMessage server) {
    final cid = server.clientMessageId;
    final idx = cid == null ? -1 : _messages.indexWhere((m) => m.clientMessageId == cid);
    _sendTimers.remove(cid)?.cancel();
    setState(() {
      _seenServerIds.add(server.id);
      if (idx == -1) {
        if (!_messages.any((m) => m.id == server.id)) _messages.add(server);
      } else {
        _messages[idx] = server.copyWith(status: MessageStatus.sent);
      }
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
  }

  void _setPartnerTyping(bool active) {
    _typingResetTimer?.cancel();
    setState(() => _partnerTyping = active);
    if (active) {
      _typingResetTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _partnerTyping = false);
      });
    }
  }

  void _markMineRead() {
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        if (m.senderId == _currentUserId && m.readAt == null) {
          _messages[i] = m.copyWith(readAt: DateTime.now());
        }
      }
    });
  }

  // ── send / typing / read ──────────────────────────────────────────

  void _send() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    _typingStopTimer?.cancel();
    _rt.sendTyping(widget.matchId, active: false);
    final clientId = uuidV4();
    final optimistic = ChatMessage(
      id: 'local:$clientId',
      matchId: widget.matchId,
      senderId: _currentUserId,
      clientMessageId: clientId,
      body: text,
      createdAt: DateTime.now(),
      status: MessageStatus.sending,
    );
    setState(() => _messages.add(optimistic));
    _dispatchSend(clientId, text);
    _scrollToBottom();
  }

  void _dispatchSend(String clientId, String body) {
    _rt.sendMessage(conversationId: widget.matchId, clientMessageId: clientId, body: body);
    _sendTimers[clientId]?.cancel();
    _sendTimers[clientId] = Timer(_sendTimeout, () {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.clientMessageId == clientId);
      if (idx != -1 && _messages[idx].status == MessageStatus.sending) {
        setState(() => _messages[idx] = _messages[idx].copyWith(status: MessageStatus.failed));
      }
    });
  }

  void _retry(ChatMessage failed) {
    final cid = failed.clientMessageId;
    if (cid == null) return;
    final idx = _messages.indexWhere((m) => m.clientMessageId == cid);
    if (idx == -1) return;
    setState(() => _messages[idx] = _messages[idx].copyWith(status: MessageStatus.sending));
    _dispatchSend(cid, failed.body); // same client id → idempotent
  }

  void _onUserTyping() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds > 1500) {
      _lastTypingSent = now;
      _rt.sendTyping(widget.matchId, active: true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 3), () => _rt.sendTyping(widget.matchId, active: false));
  }

  void _sendRead() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (!m.id.startsWith('local:')) {
        _rt.markRead(widget.matchId, m.id);
        return;
      }
    }
  }

  // ── scroll ────────────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollController.position.pixels <= 80 && !_loadingOlder && _hasMore) {
      _loadOlder();
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final partner = widget.thread?.partner;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(partner: partner),
            if (partner != null) _PartnerInfoRow(partner: partner),
            _ConnectionBanner(status: _rt.status),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _EmptyChatState(name: partner?.displayName ?? 'your match')
                      : _MessageList(
                          messages: _messages,
                          currentUserId: _currentUserId,
                          partnerAvatarUrl: partner?.avatarUrl,
                          scrollController: _scrollController,
                          onRetry: _retry,
                        ),
            ),
            if (_partnerTyping)
              _TypingIndicator(name: partner?.displayName ?? 'Your match'),
            _InputBar(
              controller: _inputController,
              sending: false,
              onSend: _send,
              onTyping: _onUserTyping,
            ),
          ],
        ),
      ),
    );
  }
}
