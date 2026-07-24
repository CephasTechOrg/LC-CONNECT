import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/providers/groups_provider.dart';
import '../../safety/providers/safety_provider.dart';
import '../../safety/widgets/safety_sheet.dart';
import '../providers/messages_provider.dart';
import '../providers/unread_provider.dart';

part '../widgets/chat_header.dart';
part '../widgets/chat_message_list.dart';
part '../widgets/chat_bubble.dart';
part '../widgets/chat_input.dart';

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
  final List<ChatMessage> _messages = []; // ascending (oldest → newest)
  final _seenServerIds = <String>{};
  final _sendTimers = <String, Timer>{}; // clientMessageId → fail-after timer

  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = true;
  bool _partnerTyping = false;
  String? _typingUserId; // who is typing (group mode → resolve to their name)
  String _currentUserId = '';
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<InboundEvent>? _eventsSub;
  StreamSubscription<void>? _reconnectSub;
  Timer? _typingResetTimer;
  Timer? _typingStopTimer;

  // Captured once in initState: reading a provider via `ref` in dispose() is
  // unsafe (the element is unmounting). The client is a session singleton, so the
  // instance never changes while this screen is mounted.
  late final RealtimeClient _rt;
  // Captured in initState so dispose() never touches `ref` while unmounting.
  late final UnreadNotifier _unread;

  @override
  void initState() {
    super.initState();
    _rt = ref.read(realtimeClientProvider);
    _currentUserId = ref.read(authNotifierProvider).asData?.value?.id ?? '';
    // Mark this chat active + optimistically zero its badge. Deferred to a microtask
    // because initState runs during the build phase and Riverpod forbids mutating a
    // provider then. Any message landing in the sub-millisecond gap is harmless — it's
    // this conversation, which `clearConversation` immediately zeroes anyway. The real
    // read still goes out via WS (_sendRead).
    _unread = ref.read(unreadProvider.notifier);
    Future.microtask(() {
      if (!mounted) return;
      _unread.enterConversation(widget.matchId);
      _unread.clearConversation(widget.matchId);
    });
    _rt.subscribe(widget.matchId);
    _eventsSub = _rt.events.listen(_onEvent);
    _reconnectSub = _rt.reconnected.listen((_) => _syncAfterReconnect());
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _unread.leaveConversation();
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
      case TypingEvent(:final conversationId, :final userId, :final active) when conversationId == widget.matchId:
        _setPartnerTyping(active, userId);
      case ReadReceipt(:final conversationId) when conversationId == widget.matchId:
        _markMineRead();
      case MessageDeleted(:final conversationId, :final messageId) when conversationId == widget.matchId:
        _markDeleted(messageId);
      default:
        break;
    }
  }

  void _markDeleted(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx == -1 || _messages[idx].deleted) return;
    setState(() => _messages[idx] = _messages[idx].copyWith(deleted: true));
  }

  /// Delete a message for everyone (optimistic; reverts + warns on failure).
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

  /// True if I'm an admin/owner of this group (may moderate — delete others' messages).
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
    if (_seenServerIds.contains(msg.id)) {
      return;
    }
    // Our own message echoed back — already reconciled via ack.
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

  /// The name to show in the typing indicator: the group member's name (falling back to
  /// "Someone" until members load), or the DM partner's name.
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

  bool get _isGroup => widget.groupId != null;

  /// Long-press a member's message → report it (group mode only). Scoped to the group so
  /// moderators know where it came from.
  /// DM ⋯ menu — report or block the partner (blocking revokes the chat, so return to the inbox).
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

  /// Sender name/avatar by user id, for group bubbles — resolved from the group's members.
  /// Empty (and identity hidden) until the members load, or for DMs.
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
    final partner = widget.thread?.partner;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ChatHeader(
              title: _isGroup ? (widget.groupTitle ?? 'Group') : (partner?.displayName ?? 'Chat'),
              avatarUrl: _isGroup ? widget.groupAvatarUrl : partner?.avatarUrl,
              isGroup: _isGroup,
              onIdentityTap: _isGroup
                  ? () => context.push('/groups/${widget.groupId}')
                  : (partner != null
                      ? () => context.push('/users/${partner.profileId}', extra: partner.displayName)
                      : null),
              onMenu: (!_isGroup && partner != null) ? () => _openDmMenu(partner) : null,
            ),
            _ConnectionBanner(status: _rt.status),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _EmptyChatState(name: widget.groupTitle ?? partner?.displayName ?? 'your match')
                      : _MessageList(
                          messages: _messages,
                          currentUserId: _currentUserId,
                          partnerAvatarUrl: partner?.avatarUrl,
                          isGroup: _isGroup,
                          senders: _senders(),
                          onReport: _isGroup ? _reportMessage : null,
                          onDelete: _deleteMessage,
                          iAmGroupAdmin: _iAmGroupAdmin,
                          scrollController: _scrollController,
                          onRetry: _retry,
                        ),
            ),
            if (_partnerTyping) _TypingIndicator(name: _typingName(partner)),
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
