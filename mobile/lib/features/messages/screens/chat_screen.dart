import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/api/api_client.dart';
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
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  final _seenIds = <String>{};
  bool _loading = true;
  bool _sending = false;
  bool _partnerTyping = false;
  String _currentUserId = '';
  RealtimeChannel? _channel;
  Timer? _typingTimer;
  Timer? _typingBroadcastDebounce;

  @override
  void initState() {
    super.initState();
    _currentUserId = ref.read(authNotifierProvider).asData?.value?.id ?? '';
    _fetchMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _typingTimer?.cancel();
    _typingBroadcastDebounce?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeToMessages() {
    try {
      _channel = Supabase.instance.client
          .channel('messages:${widget.matchId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            // No server-side UUID filter — UUID eq filter silently fails in
            // some Supabase Realtime versions. RLS already restricts events
            // to the user's own conversations; we filter by match_id here.
            callback: (payload) {
              if (!mounted) return;
              final record = payload.newRecord;
              if (record['match_id'] != widget.matchId) return;
              final msg = ChatMessage.fromJson(record);
              if (_seenIds.contains(msg.id)) return;
              setState(() {
                _seenIds.add(msg.id);
                _messages.add(msg);
              });
              _scrollToBottom();
            },
          )
          .onBroadcast(
            event: 'typing',
            callback: (_) {
              if (!mounted) return;
              setState(() => _partnerTyping = true);
              _typingTimer?.cancel();
              _typingTimer = Timer(const Duration(seconds: 3), () {
                if (mounted) setState(() => _partnerTyping = false);
              });
            },
          )
          .subscribe();
    } catch (_) {
      // Realtime unavailable; messages delivered via REST only
    }
  }

  void _onUserTyping() {
    _typingBroadcastDebounce?.cancel();
    _typingBroadcastDebounce = Timer(const Duration(milliseconds: 500), () {
      _channel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': _currentUserId},
      );
    });
  }

  Future<void> _fetchMessages() async {
    try {
      final client = ref.read(apiClientProvider);
      final response =
          await client.dio.get('/messages/threads/${widget.matchId}');
      if (!mounted) return;
      final msgs = (response.data as List)
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      setState(() {
        _messages = msgs;
        _seenIds.addAll(msgs.map((m) => m.id));
        _loading = false;
      });
      _scrollToBottom(jump: true);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    _inputController.clear();
    setState(() => _sending = true);
    try {
      final client = ref.read(apiClientProvider);
      final response = await client.dio.post(
        '/messages/threads/${widget.matchId}',
        data: {'body': text},
      );
      if (!mounted) return;
      final msg = ChatMessage.fromJson(response.data as Map<String, dynamic>);
      setState(() {
        _sending = false;
        // Add immediately; deduplicate if realtime also delivers it
        if (!_seenIds.contains(msg.id)) {
          _seenIds.add(msg.id);
          _messages.add(msg);
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Failed to send message'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (jump) {
        _scrollController
            .jumpTo(_scrollController.position.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? _EmptyChatState(
                          name: partner?.displayName ?? 'your match')
                      : _MessageList(
                          messages: _messages,
                          currentUserId: _currentUserId,
                          partnerAvatarUrl: partner?.avatarUrl,
                          scrollController: _scrollController,
                        ),
            ),
            if (_partnerTyping)
              _TypingIndicator(name: partner?.displayName ?? 'Your match'),
            _InputBar(
              controller: _inputController,
              sending: _sending,
              onSend: _send,
              onTyping: _onUserTyping,
            ),
          ],
        ),
      ),
    );
  }
}

