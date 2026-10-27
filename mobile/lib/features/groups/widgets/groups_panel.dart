import '../../../shared/util/caching.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../data/group_models.dart';
import '../data/placeholder_groups.dart' show groupCategories;
import '../providers/groups_provider.dart';
import 'create_group_sheet.dart';
import 'group_search_field.dart';
import 'pending_invites.dart';
import 'your_groups_section.dart';
import '../../messages/utils/chat_routes.dart';
import '../../../shared/widgets/app_states.dart';

/// Campus Groups panel — now wired to the live `/groups` API.
class GroupsPanel extends ConsumerStatefulWidget {
  const GroupsPanel({super.key});

  @override
  ConsumerState<GroupsPanel> createState() => _GroupsPanelState();
}

class _GroupsPanelState extends ConsumerState<GroupsPanel> {
  String _category = 'All';
  String _query = ''; // debounced group-name search
  Timer? _debounce;
  final _searchController = TextEditingController();
  final _busy = <String>{}; // group ids with a join in flight

  String? get _apiCategory =>
      _category == 'All' ? null : groupApiCategories[_category];

  DiscoverArgs get _discoverArgs =>
      (category: _apiCategory, query: _query.isEmpty ? null : _query);

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // Debounce so we hit /groups/discover once the user pauses, not on every keystroke.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _query = '');
  }

  Future<void> _join(GroupSummary group) async {
    if (_busy.contains(group.id)) return;
    setState(() => _busy.add(group.id));
    try {
      final status = await ref.read(groupsRepositoryProvider).join(group.id);
      if (!mounted) return;
      ref.invalidate(discoverGroupsProvider);
      ref.invalidate(myGroupsProvider); // joined an open group → refresh Your Groups
      _snack(
        status == 'active'
            ? 'Joined ${group.name}'
            : 'Request sent to ${group.name}',
      );
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e, fallback: 'Could not join — try again'), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(group.id));
    }
  }

  Future<void> _open(GroupSummary group) async {
    if (!group.isMember) return; // must be a member to open the chat
    try {
      // GroupSummary lacks conversation_id; fetch the full group for it.
      final full = await ref.read(groupsRepositoryProvider).get(group.id);
      if (!mounted) return;
      context.push(
        groupChatPath(full.conversationId),
        extra: GroupChatArgs(name: full.name, groupId: full.id, avatarUrl: full.avatarUrl),
      );
    } catch (_) {
      if (mounted) _snack('Could not open the group', error: true);
    }
  }

  Future<void> _createGroup() async {
    final created = await showCreateGroupSheet(context, ref);
    if (created != null && mounted) {
      ref.invalidate(discoverGroupsProvider);
      ref.invalidate(myGroupsProvider); // new group → show it in Your Groups
      _snack('Created ${created.name}');
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: Colors.white)),
        backgroundColor: error ? AppColors.textDark : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(discoverGroupsProvider(_discoverArgs));

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.invalidate(myGroupsProvider);
        ref.invalidate(myInvitesProvider);
        // Invalidate-then-read rather than `refresh`, which is `@useResult` and warned when
        // awaited for its side effect. Same behaviour, consistent with the two lines above.
        ref.invalidate(discoverGroupsProvider(_discoverArgs));
        await ref.read(discoverGroupsProvider(_discoverArgs).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
      children: [
        const PendingInvitesSection(),
        const YourGroupsSection(),
        GroupSearchField(
          controller: _searchController,
          hasText: _query.isNotEmpty,
          onChanged: _onSearchChanged,
          onClear: _clearSearch,
        ),
        AppFilterChipRow(
          labels: groupCategories,
          selected: _category,
          onSelect: (c) => setState(() => _category = c),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Row(
            children: [
              Text(
                'Discover',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              // A full 48dp target: this was shrink-wrapped to the text, the smallest control on
              // the page for the one action that starts something.
              TextButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.add_rounded, size: 18, color: AppColors.primaryText),
                label: Text(
                  'Create group',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
                style: TextButton.styleFrom(
                  minimumSize: const Size(kMinInteractiveDimension, kMinInteractiveDimension),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
              ),
            ],
          ),
        ),
        // `cached`, not `when`: a skeleton replacing a list the user is already reading is the
        // "everything reloads" complaint. Cached results stay put while fresh ones load behind.
        async.cached(
          loading: () => const AppListSkeleton(count: 2, padding: EdgeInsets.fromLTRB(20, 60, 20, 20)),
          error: (e, _) => AppInlineMessage(
            message: 'Couldn\'t load groups',
            onRetry: () => ref.invalidate(discoverGroupsProvider(_discoverArgs)),
          ),
          data: (allGroups) {
            // De-duplicate: groups you're already in appear in "Your groups", and ones you're
            // invited to appear in "Pending invites" — don't list them again here.
            final groups = discoverableGroups(allGroups);
            if (groups.isEmpty) {
              final message = _query.isNotEmpty
                  ? 'No groups match "$_query"'
                  : allGroups.isEmpty
                      ? 'No groups yet. Create the first one.'
                      : "You're in all the groups here — create a new one.";
              return AppInlineMessage(message: message);
            }
            return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      for (final g in groups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _GroupListTile(
                            group: g,
                            busy: _busy.contains(g.id),
                            onAction: () => _join(g),
                            onOpen: () => _open(g),
                          ),
                        ),
                    ],
                  ),
                );
          },
        ),
      ],
    ),
    );
  }
}


IconData _iconFor(String category) => switch (category) {
  'housing' => Icons.home_outlined,
  'class' => Icons.school_outlined,
  'club' => Icons.groups_outlined,
  _ => Icons.favorite_border_rounded,
};

String _categoryLabel(String category) => switch (category) {
  'club' => 'Clubs & Sports',
  'class' => 'Academic',
  'housing' => 'Housing',
  _ => 'Interest',
};

class _GroupListTile extends StatelessWidget {
  final GroupSummary group;
  final bool busy;
  final VoidCallback onAction;
  final VoidCallback onOpen;
  const _GroupListTile({
    required this.group,
    required this.busy,
    required this.onAction,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    // The shared card surface (borderless, soft shadow), same as Home and Activities.
    return AppCard(
      onTap: group.isMember ? onOpen : null, // members tap to open the group chat
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: AppRadii.all(AppRadii.lg),
            ),
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            child: group.avatarUrl != null
                ? CachedNetworkImage(
                    imageUrl: group.avatarUrl!,
                    fit: BoxFit.cover,
                    width: 44,
                    height: 44,
                    errorWidget: (_, _, _) =>
                        Icon(_iconFor(group.category), size: 20, color: AppColors.primaryText),
                  )
                : Icon(_iconFor(group.category), size: 20, color: AppColors.primaryText),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_categoryLabel(group.category)} · ${group.memberCount} members',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _GroupActionBtn(
            label: group.actionLabel,
            enabled: group.actionEnabled,
            joined: group.isMember,
            busy: busy,
            groupName: group.name,
            onTap: onAction,
          ),
        ],
      ),
    );
  }
}

/// The join control on a group row, on the same rule as the Activities RSVP pill: a blue fill
/// when there is something to do (Join, Request), soft blue once you are in (Joined), flat grey
/// when there is nothing to do (Pending, Invite only). It used to be five treatments — a filled
/// button, a blue outline, and three grey outlines — for one control.
class _GroupActionBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool joined;
  final bool busy;
  final String groupName;
  final VoidCallback onTap;
  const _GroupActionBtn({
    required this.label,
    required this.enabled,
    required this.joined,
    required this.busy,
    required this.groupName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = enabled
        ? (AppColors.primary, Colors.white)
        : joined
            ? (AppColors.primarySoft, AppColors.primaryText)
            : (AppColors.quiet, AppColors.textMuted);

    return Semantics(
      container: true,
      button: enabled,
      enabled: enabled,
      label: enabled ? '$label $groupName' : '$groupName: $label',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled && !busy ? onTap : null,
        // 48dp tall target around a 34dp pill.
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2),
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadii.all(AppRadii.full),
              ),
              alignment: Alignment.center,
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (joined) ...[
                          Icon(Icons.check_rounded, size: 15, color: foreground),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Text(
                          label,
                          style: AppTypography.bodySmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: foreground,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
