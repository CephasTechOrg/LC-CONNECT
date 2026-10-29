import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/util/app_date_format.dart';
import '../../auth/providers/auth_provider.dart';
import '../../messages/data/thread_preview.dart';
import '../../messages/providers/messages_provider.dart';
import '../../messages/providers/unread_provider.dart';
import '../../messages/utils/chat_routes.dart';
import '../data/group_models.dart';
import '../providers/groups_provider.dart';

/// The groups you're in, as chat rows: name, the latest message, its time and your unread count,
/// most recent first. It used to be a strip of round icons that said nothing about what was
/// happening in each group and cost 136dp before the list started.
///
/// Shows [_collapsedCount] rows with a "See all" toggle, so a student in many groups still reaches
/// Discover. Renders nothing until you've joined a group.
class YourGroupsSection extends ConsumerStatefulWidget {
  const YourGroupsSection({super.key});

  @override
  ConsumerState<YourGroupsSection> createState() => _YourGroupsSectionState();
}

class _YourGroupsSectionState extends ConsumerState<YourGroupsSection> {
  static const _collapsedCount = 4;
  bool _expanded = false;
  bool _opening = false;

  Future<void> _open(GroupSummary group) async {
    final chatId = group.chatId;
    if (chatId != null) {
      context.push(
        groupChatPath(chatId),
        extra: GroupChatArgs(name: group.name, groupId: group.id, avatarUrl: group.avatarUrl),
      );
      return;
    }
    // An older server sends no chat id with the list; fetch the group for it.
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final full = await ref.read(groupsRepositoryProvider).get(group.id);
      if (!mounted) return;
      context.push(
        groupChatPath(full.conversationId),
        extra: GroupChatArgs(name: full.name, groupId: full.id, avatarUrl: full.avatarUrl),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the group'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `.value`: keep the rows on screen while the list refreshes.
    final groups = ref.watch(myGroupsProvider).value ?? const <GroupSummary>[];
    if (groups.isEmpty) return const SizedBox.shrink();
    final threads = {
      for (final t in ref.watch(threadsNotifierProvider).value ?? const <MessageThread>[])
        if (t.isGroup) t.conversationId: t,
    };
    final sorted = sortByActivity(groups, threads);
    final visible = _expanded ? sorted : sorted.take(_collapsedCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Your groups',
          action: sorted.length > _collapsedCount
              ? (_expanded ? 'Show less' : 'See all ${sorted.length}')
              : null,
          onAction: () => setState(() => _expanded = !_expanded),
        ),
        for (final g in visible)
          _GroupChatRow(group: g, thread: g.chatId == null ? null : threads[g.chatId], onTap: () => _open(g)),
      ],
    );
  }
}

/// Most recent conversation first; groups with no messages yet keep the server's order after them.
List<GroupSummary> sortByActivity(List<GroupSummary> groups, Map<String, MessageThread> threads) {
  DateTime? lastAt(GroupSummary g) => g.chatId == null ? null : threads[g.chatId]?.latestMessage?.createdAt;
  final indexed = groups.indexed.toList();
  indexed.sort((a, b) {
    final at = lastAt(a.$2);
    final bt = lastAt(b.$2);
    if (at == null && bt == null) return a.$1.compareTo(b.$1);
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return [for (final (_, g) in indexed) g];
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _SectionTitle({required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: [
          Text(title, style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                action!,
                style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600, color: AppColors.primaryText),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupChatRow extends ConsumerWidget {
  final GroupSummary group;
  final MessageThread? thread;
  final VoidCallback onTap;
  const _GroupChatRow({required this.group, required this.thread, required this.onTap});

  static const _avatar = 44.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatId = group.chatId;
    final unread = chatId == null ? 0 : ref.watch(unreadProvider.select((s) => s.countFor(chatId)));
    final myId = ref.watch(authNotifierProvider.select((a) => a.value?.id)) ?? '';
    final latest = thread?.latestMessage;
    final preview = thread == null ? null : threadPreview(thread!, myId);
    final role = group.myGroupRole;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: AppSpacing.sm),
        child: Row(
          children: [
            _GroupAvatar(url: group.avatarUrl, size: _avatar),
            const SizedBox(width: AppSpacing.md),
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
                                group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                            ),
                            if (role == 'owner' || role == 'admin') ...[
                              const SizedBox(width: 6),
                              _RoleTag(label: role == 'owner' ? 'Owner' : 'Admin'),
                            ],
                          ],
                        ),
                      ),
                      if (latest != null) const SizedBox(width: AppSpacing.sm),
                      if (latest != null)
                        Text(
                          AppDateFormat.listStamp(latest.createdAt),
                          style: AppTypography.caption.copyWith(
                            color: unread > 0 ? AppColors.primaryText : AppColors.textMuted,
                            fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview?.text ?? '${group.memberCount} members',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: unread > 0 ? AppColors.textDark : AppColors.textMuted,
                            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                            fontStyle: (preview?.italic ?? false) ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ),
                      if (thread?.muted ?? false) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.notifications_off_outlined, size: 15, color: AppColors.textMuted),
                      ],
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        _UnreadDot(count: unread, muted: thread?.muted ?? false),
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

class _GroupAvatar extends StatelessWidget {
  final String? url;
  final double size;
  const _GroupAvatar({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    const fallback = Icon(Icons.groups_outlined, size: 22, color: AppColors.primary);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
      child: url == null
          ? fallback
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}

class _RoleTag extends StatelessWidget {
  final String label;
  const _RoleTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: AppTypography.micro.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryText),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  final int count;
  final bool muted;
  const _UnreadDot({required this.count, required this.muted});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? AppColors.textMuted : AppColors.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.2),
      ),
    );
  }
}
