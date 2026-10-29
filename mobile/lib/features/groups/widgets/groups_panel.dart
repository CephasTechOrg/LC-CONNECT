import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/util/caching.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../../messages/utils/chat_routes.dart';
import '../data/group_models.dart';
import '../providers/groups_provider.dart';
import 'create_group_sheet.dart';
import 'group_list_tile.dart';
import 'groups_discover_header.dart';
import 'pending_invites.dart';
import 'your_groups_section.dart';

/// The Groups page: invites (compact), your groups as chat rows, then Discover under a pinned
/// search-and-filter bar, one page at a time.
class GroupsPanel extends ConsumerStatefulWidget {
  const GroupsPanel({super.key});

  @override
  ConsumerState<GroupsPanel> createState() => _GroupsPanelState();
}

class _GroupsPanelState extends ConsumerState<GroupsPanel> {
  String _chip = 'All';
  String _sort = 'popular';
  String _query = ''; // debounced group-name search
  int _pages = 1;
  Timer? _debounce;
  final _searchController = TextEditingController();
  final _busy = <String>{}; // group ids with a join in flight

  DiscoverArgs _args(int page) =>
      (category: groupCategoryChips[_chip], query: _query.isEmpty ? null : _query, sort: _sort, page: page);

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Any filter change starts Discover again from its first page.
  void _setFilters(VoidCallback change) => setState(() {
        change();
        _pages = 1;
      });

  void _onSearchChanged(String value) {
    // Debounce so we hit /groups/discover once the user pauses, not on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _setFilters(() => _query = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _setFilters(() => _query = '');
  }

  Future<void> _join(GroupSummary group) async {
    if (_busy.contains(group.id)) return;
    setState(() => _busy.add(group.id));
    try {
      final status = await ref.read(groupsRepositoryProvider).join(group.id);
      if (!mounted) return;
      ref.invalidate(discoverGroupsProvider);
      ref.invalidate(myGroupsProvider); // joined an open group → it moves up to Your groups
      _snack(status == 'active' ? 'Joined ${group.name}' : 'Request sent to ${group.name}');
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e, fallback: 'Could not join — try again'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(group.id));
    }
  }

  Future<void> _createGroup() async {
    final created = await showCreateGroupSheet(context, ref);
    if (created != null && mounted) {
      ref.invalidate(discoverGroupsProvider);
      ref.invalidate(myGroupsProvider); // new group → show it in Your groups
      _snack('Created ${created.name}');
      context.push(
        groupChatPath(created.conversationId),
        extra: GroupChatArgs(name: created.name, groupId: created.id, avatarUrl: created.avatarUrl),
      );
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: error ? AppColors.textDark : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(myGroupsProvider);
    ref.invalidate(myInvitesProvider);
    ref.invalidate(discoverGroupsProvider);
    setState(() => _pages = 1);
    await ref.read(discoverGroupsProvider(_args(0)).future);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: PendingInvitesSection()),
          const SliverToBoxAdapter(child: YourGroupsSection()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Text(
                'Discover',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w700, color: AppColors.textDark),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: GroupsDiscoverHeader(
              searchController: _searchController,
              hasQuery: _query.isNotEmpty,
              onSearchChanged: _onSearchChanged,
              onClearSearch: _clearSearch,
              selectedChip: _chip,
              onSelectChip: (c) => _setFilters(() => _chip = c),
              sort: _sort,
              onSort: (s) => _setFilters(() => _sort = s),
              onCreate: _createGroup,
            ),
          ),
          ..._discoverSlivers(),
        ],
      ),
    );
  }

  List<Widget> _discoverSlivers() {
    final first = ref.watch(discoverGroupsProvider(_args(0)));
    // `cached`, not `when`: a skeleton replacing a list the user is already reading is the
    // "everything reloads" complaint. Cached results stay put while fresh ones load behind.
    return first.cached(
      loading: () => [
        const SliverToBoxAdapter(
          child: AppListSkeleton(count: 3, padding: EdgeInsets.fromLTRB(20, 12, 20, 20)),
        ),
      ],
      error: (e, _) => [
        SliverToBoxAdapter(
          child: AppInlineMessage(
            message: "Couldn't load groups",
            onRetry: () => ref.invalidate(discoverGroupsProvider(_args(0))),
          ),
        ),
      ],
      data: (firstPage) {
        final groups = [...firstPage];
        var lastPage = firstPage;
        var loadingMore = false;
        for (var page = 1; page < _pages; page++) {
          final next = ref.watch(discoverGroupsProvider(_args(page)));
          final rows = next.value;
          if (rows == null) {
            loadingMore = true;
            break;
          }
          groups.addAll(rows);
          lastPage = rows;
        }
        // The server already leaves these out; an older one did not.
        final visible = discoverableGroups(groups);
        if (visible.isEmpty) {
          final message = _query.isNotEmpty
              ? 'No groups match "$_query"'
              : _chip != 'All'
                  ? 'No ${_chip.toLowerCase()} to join yet.'
                  : "You're in every group here — create a new one.";
          return [SliverToBoxAdapter(child: AppInlineMessage(message: message))];
        }
        final hasMore = lastPage.length >= kDiscoverPageSize;
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) => GroupListTile(
                group: visible[i],
                busy: _busy.contains(visible[i].id),
                onAction: () => _join(visible[i]),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: loadingMore
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : hasMore
                      ? TextButton(
                          onPressed: () => setState(() => _pages++),
                          child: const Text('Show more groups'),
                        )
                      : const SizedBox.shrink(),
            ),
          ),
        ];
      },
    );
  }
}
