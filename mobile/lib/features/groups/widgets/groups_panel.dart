import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../data/group_models.dart';
import '../data/placeholder_groups.dart' show groupCategories;
import '../providers/groups_provider.dart';
import 'create_group_sheet.dart';
import 'group_search_field.dart';
import 'pending_invites.dart';
import 'your_groups_section.dart';

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
        '/messages/group/${full.conversationId}',
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
        content: Text(message, style: GoogleFonts.dmSans(color: Colors.white)),
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
        await ref.refresh(discoverGroupsProvider(_discoverArgs).future);
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
                'All Groups',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _createGroup,
                icon: const Icon(Icons.add, size: 14, color: AppColors.primary),
                label: Text(
                  'Create Group',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 60),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _PanelMessage(
            text: 'Couldn\'t load groups',
            onRetry: () => ref.invalidate(discoverGroupsProvider(_discoverArgs)),
          ),
          data: (groups) => groups.isEmpty
              ? _PanelMessage(
                  text: _query.isNotEmpty
                      ? 'No groups match "$_query"'
                      : 'No groups yet — create the first one!',
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      for (final g in groups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: _GroupListTile(
                            group: g,
                            busy: _busy.contains(g.id),
                            onAction: () => _join(g),
                            onOpen: () => _open(g),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const _PanelMessage({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Text(
            text,
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: GoogleFonts.dmSans(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: group.isMember
            ? onOpen
            : null, // members tap to open the group chat
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: group.avatarUrl != null
                    ? Image.network(
                        group.avatarUrl!,
                        fit: BoxFit.cover,
                        width: 42,
                        height: 42,
                        errorBuilder: (_, _, _) => Icon(
                          _iconFor(group.category),
                          size: 18,
                          color: AppColors.primary,
                        ),
                      )
                    : Icon(
                        _iconFor(group.category),
                        size: 18,
                        color: AppColors.primary,
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      '${_categoryLabel(group.category)} · ${group.memberCount} members',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _GroupActionBtn(
                label: group.actionLabel,
                enabled: group.actionEnabled,
                busy: busy,
                onTap: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupActionBtn extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const _GroupActionBtn({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, border, color) = switch (label) {
      'Join' ||
      'Accept' => (AppColors.primary, AppColors.primary, Colors.white),
      'Joined' => (AppColors.surface, AppColors.border, AppColors.textMid),
      'Request' => (AppColors.surface, AppColors.primary, AppColors.primary),
      _ => (AppColors.surface, AppColors.border, AppColors.textMuted),
    };

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: enabled && !busy ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: border, width: 1.5),
          ),
          child: busy
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
        ),
      ),
    );
  }
}
