import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/util/app_date_format.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/verified_badge.dart';
import '../providers/messages_provider.dart';
import '../providers/staff_messaging_provider.dart';
import '../providers/unread_provider.dart';
import '../widgets/message_status_icon.dart';
import '../../auth/providers/auth_provider.dart';
import '../../groups/data/group_models.dart';
import '../utils/chat_routes.dart';
import '../widgets/messages_segments.dart';
import '../widgets/staff_tag.dart';
import '../data/thread_preview.dart';
import '../data/message_search.dart';
import '../data/thread_order.dart';
import '../providers/inbox_drafts_provider.dart';
import '../providers/message_search_provider.dart';
import '../../../core/api/api_error.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/ws_protocol.dart';
import '../../../shared/util/caching.dart';

part '../widgets/thread_row.dart';
part '../widgets/thread_actions.dart';
part '../widgets/archived_chats.dart';
part '../widgets/message_search_results.dart';

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
              onPressed: () => context.push(newMessagePath),
              tooltip: 'New message',
              backgroundColor: AppColors.primary,
              // Round, like the Activities create button: one shape for "make something new".
              shape: const CircleBorder(),
              child: const Icon(Icons.edit_outlined, color: Colors.white),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            const AppShellHeader(title: 'Messages'),
            const MessagesSegments(active: MessagesSegment.chats),
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
              child: async.cached(
                loading: () => const AppThreadListSkeleton(),
                error: (e, _) => _ErrorState(
                  onRetry: () => ref.invalidate(threadsNotifierProvider),
                ),
                data: (threads) {
                  final arranged = arrangeInbox(threads);
                  // Searching looks through archived chats too, and through message text.
                  final searching = _query.isNotEmpty;
                  final visible = searching ? _filter(threads) : arranged.main;
                  final hits = searching
                      ? ref.watch(messageSearchProvider(_query)).value ?? const <MessageSearchHit>[]
                      : const <MessageSearchHit>[];
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(threadsNotifierProvider),
                    child: threads.isEmpty
                        ? _EmptyState(canMessageAnyone: canMessageAnyone)
                        : visible.isEmpty && hits.isEmpty && arranged.archived.isEmpty
                            ? _NoMatches(query: _query)
                            : _ThreadList(
                                threads: visible,
                                leading: !searching && arranged.archived.isNotEmpty
                                    ? _ArchivedRow(archived: arranged.archived)
                                    : null,
                                trailing: hits.isEmpty ? null : _MessageSearchResults(hits: hits, threads: threads),
                              ),
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

  /// Above the rows (the Archived row) and below them (message search results).
  final Widget? leading;
  final Widget? trailing;
  const _ThreadList({required this.threads, this.leading, this.trailing});

  @override
  Widget build(BuildContext context) {
    final extraTop = leading == null ? 0 : 1;
    return ListView.separated(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 88),
      itemCount: threads.length + extraTop + (trailing == null ? 0 : 1),
      // Starts under the text, not the avatar, so each row reads as one unit.
      separatorBuilder: (context, _) => const Divider(
        height: 1,
        indent: AppSpacing.gutter + _ThreadCard.avatarSize + AppSpacing.md,
        endIndent: AppSpacing.gutter,
        color: AppColors.border,
      ),
      itemBuilder: (_, i) {
        if (leading != null && i == 0) return leading!;
        final index = i - extraTop;
        if (index >= threads.length) return trailing!;
        return _ThreadCard(thread: threads[index]);
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool canMessageAnyone;
  const _EmptyState({required this.canMessageAnyone});

  @override
  Widget build(BuildContext context) {
    return AppScrollableEmptyState(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'No messages yet',
      subtitle: canMessageAnyone
          ? 'Tap the compose button to message any student or staff member.'
          : 'Accept a connection request to start chatting.',
      topFraction: 0.18,
    );
  }
}

// ── No search matches ─────────────────────────────────────────────
class _NoMatches extends StatelessWidget {
  final String query;
  const _NoMatches({required this.query});

  @override
  Widget build(BuildContext context) {
    // Was bare centred text with no icon — the only no-results state in the app that looked
    // nothing like its siblings.
    return AppScrollableEmptyState(
      icon: Icons.search_off_rounded,
      title: 'No conversations found',
      subtitle: 'Nothing matches "$query".',
      topFraction: 0.14,
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
