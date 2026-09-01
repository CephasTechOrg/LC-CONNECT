import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';
import '../../safety/providers/safety_provider.dart';
import '../../safety/widgets/safety_sheet.dart';
import '../providers/messages_provider.dart';
import '../providers/unread_provider.dart';
import '../data/chat_message_cache.dart';

part '../widgets/chat_header.dart';
part '../widgets/chat_message_list.dart';
part '../widgets/chat_bubble.dart';
part '../widgets/chat_input.dart';
part '../widgets/chat_unavailable.dart';
part '../widgets/chat_screen_body.dart';

/// Pixels from the bottom of the list before we treat the user as "scrolled up".
const _kScrollBottomThreshold = 96.0;

class ChatScreen extends ConsumerStatefulWidget {
  /// For a DM this is the match id; for a group it's the group's conversation id — the
  /// backend resolves either. `groupTitle` set ⇒ group mode (no partner card). `groupId`,
  /// when known, lets the header open the group detail/admin screen.
  final String matchId;
  final MessageThread? thread;
  final String? groupTitle;
  final String? groupId;
  final String? groupAvatarUrl;

  const ChatScreen({
    super.key,
    required this.matchId,
    this.thread,
    this.groupTitle,
    this.groupId,
    this.groupAvatarUrl,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _pageSize = 50;
  static const _sendTimeout = Duration(seconds: 8);

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final _seenServerIds = <String>{};
  final _sendTimers = <String, Timer>{};

  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  String? _loadError;
  bool _partnerTyping = false;
  String? _typingUserId;
  bool _awayFromBottom = false;
  int _newWhileAway = 0;
  String _currentUserId = '';
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<InboundEvent>? _eventsSub;
  StreamSubscription<void>? _reconnectSub;
  Timer? _typingResetTimer;
  Timer? _typingStopTimer;
  Timer? _cacheSaveTimer;

  late final RealtimeClient _rt;
  late final UnreadNotifier _unread;

  @override
  void initState() {
    super.initState();
    _rt = ref.read(realtimeClientProvider);
    _currentUserId = ref.read(authNotifierProvider).asData?.value?.id ?? '';
    _unread = ref.read(unreadProvider.notifier);
    if (!_validThread) {
      _loading = false;
      return;
    }
    // Must run after the first frame — Riverpod forbids notifier writes during build.
    Future.microtask(() {
      if (!mounted) return;
      _unread.enterConversation(widget.matchId);
      _unread.clearConversation(widget.matchId);
      _rt.subscribe(widget.matchId);
    });
    _eventsSub = _rt.events.listen(_onEvent);
    _reconnectSub = _rt.reconnected.listen((_) => _syncAfterReconnect());
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    if (_validThread) {
      _unread.leaveConversation();
      _rt.unsubscribe(widget.matchId);
    }
    _eventsSub?.cancel();
    _reconnectSub?.cancel();
    _typingResetTimer?.cancel();
    _typingStopTimer?.cancel();
    _cacheSaveTimer?.cancel();
    for (final t in _sendTimers.values) {
      t.cancel();
    }
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    if (!_validThread) return;
    final cached = await ref.read(chatMessageCacheProvider).load(widget.matchId);
    if (mounted && cached != null && cached.isNotEmpty) {
      setState(() {
        _absorb(cached);
        _loading = false;
      });
      _scrollToBottom(jump: true, force: true);
    }
    try {
      final resp = await ref
          .read(apiClientProvider)
          .dio
          .get('/messages/threads/${widget.matchId}', queryParameters: {'limit': _pageSize});
      if (!mounted) return;
      final page = _parsePage(resp.data as List);
      setState(() {
        _absorb(page);
        _hasMore = page.length >= _pageSize;
        _loading = false;
        _loadError = null;
      });
      _scrollToBottom(jump: true, force: true);
      _sendRead();
      _scheduleCacheSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_messages.isEmpty) {
          _loadError = apiErrorMessage(
            e,
            fallback: 'Could not load this conversation. Check your connection and try again.',
          );
        }
      });
    }
  }

  void _retryLoadInitial() {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _loadInitial();
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    final oldest = _messages.first;
    if (oldest.id.startsWith('local:')) return;
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
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _syncAfterReconnect() async {
    if (!_validThread) return;
    _rt.subscribe(widget.matchId);
    final newest = _newestServerMessage();
    if (newest == null) return _loadInitial();
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
        final missed = _parseAscending(resp.data as List);
        if (missed.isEmpty) break;
        setState(() => _absorb(missed));
        totalMissed += missed.length;
        if (missed.length < 100) break;
        cursor = missed.last;
      }
      if (totalMissed > 0) {
        if (_isNearBottom) {
          _scrollToBottom();
        } else {
          setState(() => _newWhileAway += totalMissed);
        }
        _scheduleCacheSave();
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
        continue;
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
    final liveIds = merged.map((m) => m.id).toSet();
    _seenServerIds.removeWhere((id) => !liveIds.contains(id));
  }

  void _scheduleCacheSave() {
    _cacheSaveTimer?.cancel();
    _cacheSaveTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || !_validThread) return;
      ref.read(chatMessageCacheProvider).save(widget.matchId, _messages);
    });
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= _kScrollBottomThreshold;
  }

  void _onEvent(InboundEvent event) {
    if (!mounted) return;
    switch (event) {
      case MessageCreated(:final conversationId, :final message) when conversationId == widget.matchId:
        _mergeIncoming(ChatMessage.fromJson(message));
        _sendRead();
      case MessageAck(:final message) when message['conversation_id'] == widget.matchId:
        _reconcileAck(ChatMessage.fromJson(message));
      case TypingEvent(:final conversationId, :final userId, :final active) when conversationId == widget.matchId:
        _setPartnerTyping(active, userId);
      case ReadReceipt(:final conversationId) when conversationId == widget.matchId:
        _markMineRead();
      case MessageDeleted(:final conversationId, :final messageId) when conversationId == widget.matchId:
        _markDeleted(messageId);
      case WsError(:final code, :final message):
        _handleWsError(code, message);
      default:
        break;
    }
  }

  void _handleWsError(String code, String message) {
    if (code != 'rate_limited' && code != 'forbidden') return;
    var failed = false;
    setState(() {
      for (var i = 0; i < _messages.length; i++) {
        if (_messages[i].status == MessageStatus.sending) {
          _messages[i] = _messages[i].copyWith(status: MessageStatus.failed);
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

  void _markDeleted(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1 || _messages[idx].deleted) return;
    setState(() => _messages[idx] = _messages[idx].copyWith(deleted: true));
  }

  Future<void> _deleteMessage(ChatMessage msg) async {
    _markDeleted(msg.id);
    try {
      await ref.read(apiClientProvider).dio.delete('/messages/${msg.id}');
    } catch (_) {
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx != -1) setState(() => _messages[idx] = _messages[idx].copyWith(deleted: false));
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

  bool get _iAmGroupAdmin {
    if (!_isGroup) return false;
    final members = ref.watch(groupMembersProvider(widget.groupId!)).asData?.value;
    if (members == null) return false;
    for (final m in members) {
      if (m.userId == _currentUserId) return m.role == 'admin' || m.role == 'owner';
    }
    return false;
  }

  void _mergeIncoming(ChatMessage msg) {
    if (_seenServerIds.contains(msg.id)) return;
    if (msg.clientMessageId != null &&
        _messages.any((m) => m.clientMessageId == msg.clientMessageId)) {
      _seenServerIds.add(msg.id);
      return;
    }
    setState(() {
      _seenServerIds.add(msg.id);
      _messages.add(msg);
      _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    });
    final isMine = msg.senderId == _currentUserId;
    if (isMine || _isNearBottom) {
      _scrollToBottom(force: true);
    } else {
      setState(() => _newWhileAway++);
    }
    _scheduleCacheSave();
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
    _scheduleCacheSave();
  }

  void _setPartnerTyping(bool active, [String? userId]) {
    _typingResetTimer?.cancel();
    setState(() {
      _partnerTyping = active;
      _typingUserId = active ? userId : null;
    });
    if (active) {
      _typingResetTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _partnerTyping = false);
      });
    }
  }

  String _typingName(MessagePartner? partner) {
    if (_isGroup) return _senders()[_typingUserId]?.name ?? 'Someone';
    return partner?.displayName ?? 'Your match';
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

  void _send() {
    if (!_validThread) return;
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
    _scrollToBottom(force: true);
    _scheduleCacheSave();
  }

  void _dispatchSend(String clientId, String body) {
    final accepted = _rt.sendMessage(
      conversationId: widget.matchId,
      clientMessageId: clientId,
      body: body,
    );
      if (!accepted) {
      _sendTimers.remove(clientId)?.cancel();
      if (!mounted) return;
      final idx = _messages.indexWhere((m) => m.clientMessageId == clientId);
      if (idx != -1) {
        setState(() => _messages[idx] = _messages[idx].copyWith(status: MessageStatus.failed));
      }
      _scheduleCacheSave();
      _showOutboxFullSnack(context);
      return;
    }
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
    _dispatchSend(cid, failed.body);
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

  void _onScroll() {
    final nearBottom = _isNearBottom;
    if (nearBottom != !_awayFromBottom) {
      setState(() {
        _awayFromBottom = !nearBottom;
        if (nearBottom) _newWhileAway = 0;
      });
    }
    if (_scrollController.position.pixels <= 80 && !_loadingOlder && _hasMore) {
      _loadOlder();
    }
  }

  void _scrollToBottomTap() {
    setState(() {
      _awayFromBottom = false;
      _newWhileAway = 0;
    });
    _scrollToBottom(force: true);
  }

  void _scrollToBottom({bool jump = false, bool force = false}) {
    if (!force && _awayFromBottom) return;
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

  bool get _isGroup => widget.groupId != null;
  bool get _validThread => _isValidThreadId(widget.matchId);

  void _openDmMenu(MessagePartner partner) {
    showSafetySheet(
      context: context,
      targetUserId: partner.userId,
      targetName: partner.displayName ?? 'this student',
      safetyService: ref.read(safetyServiceProvider),
      onBlocked: () {
        if (mounted) context.go('/messages');
      },
    );
  }

  void _reportMessage(ChatMessage message) {
    showReportMessageSheet(
      context: context,
      messageId: message.id,
      groupId: widget.groupId,
      safetyService: ref.read(safetyServiceProvider),
    );
  }

  Map<String, MessageSender> _senders() {
    if (!_isGroup) return const {};
    final members = ref.watch(groupMembersProvider(widget.groupId!)).asData?.value;
    if (members == null) return const {};
    return {
      for (final m in members)
        m.userId: MessageSender(name: m.nameOrFallback, avatarUrl: m.avatarUrl, profileId: m.profileId),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!_validThread) return const _UnavailableChat();
    final partner = widget.thread?.partner;

    return _ChatScreenBody(
      partner: partner,
      partnerSubtitle: widget.thread?.partnerSubtitle,
      loading: _loading,
      loadError: _loadError,
      messages: _messages,
      currentUserId: _currentUserId,
      isGroup: _isGroup,
      groupTitle: widget.groupTitle,
      groupId: widget.groupId,
      groupAvatarUrl: widget.groupAvatarUrl,
      senders: _senders(),
      iAmGroupAdmin: _iAmGroupAdmin,
      awayFromBottom: _awayFromBottom,
      newWhileAway: _newWhileAway,
      partnerTyping: _partnerTyping,
      typingName: _typingName(partner),
      inputController: _inputController,
      scrollController: _scrollController,
      connectionStatus: _rt.status,
      outboxCount: _rt.outboxCount,
      onRetryLoad: _retryLoadInitial,
      onReport: _reportMessage,
      onDelete: _deleteMessage,
      onRetry: _retry,
      onScrollToBottomTap: _scrollToBottomTap,
      onSend: _send,
      onTyping: _onUserTyping,
      onIdentityTap: _isGroup
          ? () => context.push('/groups/${widget.groupId}')
          : (partner != null
              ? () => context.push('/users/${partner.profileId}', extra: partner.displayName)
              : null),
      onMenu: (!_isGroup && partner != null) ? () => _openDmMenu(partner) : null,
    );
  }
}
