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
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'match_id',
              value: widget.matchId,
            ),
            callback: (payload) {
              if (!mounted) return;
              final msg = ChatMessage.fromJson(payload.newRecord);
              if (_seenIds.contains(msg.id)) return;
              setState(() {
                _seenIds.add(msg.id);
                _messages.add(msg);
              });
              _scrollToBottom();
            },
          )
          .subscribe();
    } catch (_) {
      // Realtime unavailable; messages delivered via REST only
    }
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
            _InputBar(
              controller: _inputController,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat header ───────────────────────────────────────────────────
class _ChatHeader extends StatelessWidget {
  final MessagePartner? partner;
  const _ChatHeader({this.partner});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: AppColors.textDark),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              'LC',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Messages',
              style: GoogleFonts.dmSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
          const Icon(Icons.edit_outlined,
              size: 20, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

// ── Partner info row ──────────────────────────────────────────────
class _PartnerInfoRow extends StatelessWidget {
  final MessagePartner partner;
  const _PartnerInfoRow({required this.partner});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarWidget(imageUrl: partner.avatarUrl, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.displayName ?? 'LC Student',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'Livingstone College',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.more_horiz_rounded,
                  color: AppColors.textMuted, size: 22),
            ],
          ),
          // Interest/looking-for tags
          if (partner.lookingFor.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: partner.lookingFor
                  .take(3)
                  .map((label) => _Tag(label: label))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withAlpha(50)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── Message list ──────────────────────────────────────────────────
class _MessageList extends StatelessWidget {
  final List<ChatMessage> messages;
  final String currentUserId;
  final String? partnerAvatarUrl;
  final ScrollController scrollController;
  const _MessageList({
    required this.messages,
    required this.currentUserId,
    this.partnerAvatarUrl,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    // Build list with date separators
    final items = <_ListItem>[];
    DateTime? lastDate;

    for (final msg in messages) {
      final local = msg.createdAt.toLocal();
      final msgDate = DateTime(local.year, local.month, local.day);
      if (lastDate == null || msgDate != lastDate) {
        items.add(_DateSeparatorItem(msgDate));
        lastDate = msgDate;
      }
      items.add(_MessageItem(msg));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item is _DateSeparatorItem) {
          return _DateSeparator(date: item.date);
        }
        final msg = (item as _MessageItem).message;
        final isMine = msg.senderId == currentUserId;
        return _BubbleTile(
          message: msg, 
          isMine: isMine,
          partnerAvatarUrl: partnerAvatarUrl,
        );
      },
    );
  }
}

// List item types for interleaving date separators and bubbles
abstract class _ListItem {}

class _DateSeparatorItem extends _ListItem {
  final DateTime date;
  _DateSeparatorItem(this.date);
}

class _MessageItem extends _ListItem {
  final ChatMessage message;
  _MessageItem(this.message);
}

// ── Date separator ────────────────────────────────────────────────
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(),
              style: GoogleFonts.dmSans(
                fontSize: 12,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────
class _BubbleTile extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final String? partnerAvatarUrl;
  const _BubbleTile({
    required this.message, 
    required this.isMine,
    this.partnerAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            AvatarWidget(imageUrl: partnerAvatarUrl, size: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMine ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isMine ? 18 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 18),
                    ),
                    border: isMine
                        ? null
                        : Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(10),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  child: Text(
                    message.body,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      color: isMine ? Colors.white : AppColors.textDark,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  DateFormat('h:mm a').format(message.createdAt.toLocal()),
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (isMine) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.textMuted, size: 26),
            onPressed: () {},
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.textDark),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: sending ? AppColors.primarySoft : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty chat ────────────────────────────────────────────────────
class _EmptyChatState extends StatelessWidget {
  final String name;
  const _EmptyChatState({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.waving_hand_rounded,
                size: 48, color: AppColors.border),
            const SizedBox(height: 16),
            Text(
              'Start the conversation',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Say hello to $name!',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  fontSize: 13, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
