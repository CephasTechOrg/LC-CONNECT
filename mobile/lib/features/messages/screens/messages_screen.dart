import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../providers/messages_provider.dart';
import '../providers/staff_messaging_provider.dart';
import '../providers/unread_provider.dart';
import '../../groups/data/group_models.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _query = '');
  }

  List<MessageThread> _filter(List<MessageThread> threads) => _query.isEmpty
      ? threads
      : threads.where((t) => t.title.toLowerCase().contains(_query)).toList();

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(threadsNotifierProvider);
    final canMessageAnyone = ref.watch(canMessageAnyoneProvider).asData?.value ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: canMessageAnyone
          ? FloatingActionButton(
              onPressed: () => context.push('/messages/new'),
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.edit_outlined, color: Colors.white),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            const AppShellHeader(title: 'Messages'),
            // Search only appears once there are conversations to search.
            if ((async.asData?.value ?? const []).isNotEmpty)
              AppSearchField(
                controller: _searchController,
                hasText: _query.isNotEmpty,
                hint: 'Search messages',
                onChanged: _onSearch,
                onClear: _clearSearch,
              ),
            Expanded(
              child: async.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(
                  onRetry: () => ref.invalidate(threadsNotifierProvider),
                ),
                data: (threads) {
                  final visible = _filter(threads);
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(threadsNotifierProvider),
                    child: threads.isEmpty
                        ? _EmptyState(canMessageAnyone: canMessageAnyone)
                        : visible.isEmpty
                            ? _NoMatches(query: _query)
                            : _ThreadList(threads: visible),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Thread list ───────────────────────────────────────────────────
class _ThreadList extends StatelessWidget {
  final List<MessageThread> threads;
  const _ThreadList({required this.threads});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: threads.length,
      separatorBuilder: (context, _) => const Divider(
        height: 1,
        indent: 84,
        endIndent: 20,
        color: AppColors.border,
      ),
      itemBuilder: (_, i) => _ThreadCard(thread: threads[i]),
    );
  }
}

class _ThreadCard extends ConsumerWidget {
  final MessageThread thread;
  const _ThreadCard({required this.thread});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = thread.latestMessage;
    final unread = ref.watch(unreadProvider.select((s) => s.countFor(thread.addressingId)));

    return InkWell(
      onTap: () => thread.isGroup
          ? context.push('/messages/group/${thread.conversationId}',
              extra: GroupChatArgs(
                  name: thread.groupName ?? 'Group', groupId: thread.groupId, avatarUrl: thread.avatarUrl))
          : context.push('/messages/${thread.addressingId}', extra: thread),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            AvatarWidget(imageUrl: thread.avatarUrl, size: 52),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                thread.title,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.dmSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                            if (!thread.isGroup && (thread.partner?.isVerified ?? false)) ...[
                              const SizedBox(width: 4),
                              const VerifiedBadge(size: 14),
                            ],
                          ],
                        ),
                      ),
                      if (latest != null)
                        Text(
                          _formatThreadTime(latest.createdAt),
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                  if (!thread.isGroup && (thread.partnerSubtitle ?? thread.partner?.major) != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      thread.partnerSubtitle ?? thread.partner!.major!,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: thread.partnerTyping
                            ? Text(
                                'typing…',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Text(
                                latest?.body ?? 'No messages yet — say hello!',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  // Unread → darker + semibold (WhatsApp-style emphasis).
                                  color: unread > 0
                                      ? AppColors.textDark
                                      : (latest != null
                                          ? AppColors.textMid
                                          : AppColors.textMuted),
                                  fontWeight:
                                      unread > 0 ? FontWeight.w600 : FontWeight.w400,
                                  fontStyle: latest == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadBubble(count: unread),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Unread count bubble ───────────────────────────────────────────
class _UnreadBubble extends StatelessWidget {
  final int count;
  const _UnreadBubble({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool canMessageAnyone;
  const _EmptyState({required this.canMessageAnyone});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        AppEmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'No messages yet',
          subtitle: canMessageAnyone
              ? 'Tap the compose button to message any student or staff member.'
              : 'Accept a connection request to start chatting.',
        ),
      ],
    );
  }
}

// ── No search matches ─────────────────────────────────────────────
class _NoMatches extends StatelessWidget {
  final String query;
  const _NoMatches({required this.query});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.14),
        Center(
          child: Text(
            'No conversations match "$query"',
            style: GoogleFonts.dmSans(color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

// ── Error state ───────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AppErrorState(
      message: "Couldn't load messages",
      onRetry: onRetry,
    );
  }
}

// ── Time formatter ────────────────────────────────────────────────
String _formatThreadTime(DateTime dt) {
  final local = dt.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return DateFormat('EEE').format(local);
  return DateFormat('MMM d').format(local);
}
