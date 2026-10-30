import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../data/group_models.dart';
import 'group_search_field.dart';

/// Discover's controls — search, sort, create, and one row of category filters — pinned under the
/// page header while the list scrolls beneath them.
///
/// These used to be four separate blocks (search, chips, a "Discover" title row and a full-width
/// "Create group" button) taking about 186dp, scrolling away with the list. Search, sort and
/// create now share one row.
class GroupsDiscoverHeader extends SliverPersistentHeaderDelegate {
  GroupsDiscoverHeader({
    required this.searchController,
    required this.hasQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.selectedChip,
    required this.onSelectChip,
    required this.sort,
    required this.onSort,
    required this.onCreate,
  });

  static const height = 112.0;

  final TextEditingController searchController;
  final bool hasQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final String selectedChip;
  final ValueChanged<String> onSelectChip;
  final String sort; // popular | new
  final ValueChanged<String> onSort;
  final VoidCallback onCreate;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  bool shouldRebuild(GroupsDiscoverHeader old) => true;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        // A hairline only once the list runs underneath, so the header reads as part of the page
        // until then.
        border: Border(
          bottom: BorderSide(color: shrinkOffset > 0 || overlapsContent ? AppColors.border : Colors.transparent),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: GroupSearchField(
                    controller: searchController,
                    hasText: hasQuery,
                    onChanged: onSearchChanged,
                    onClear: onClearSearch,
                    padding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Sort groups',
                  icon: const Icon(Icons.sort_rounded, color: AppColors.textMid),
                  initialValue: sort,
                  onSelected: onSort,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'popular', child: Text('Most members')),
                    PopupMenuItem(value: 'new', child: Text('Newest')),
                  ],
                ),
                IconButton(
                  tooltip: 'Create group',
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryText),
                ),
              ],
            ),
          ),
          AppFilterChipRow(
            labels: groupCategoryChips.keys.toList(),
            selected: selectedChip,
            onSelect: onSelectChip,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          ),
        ],
      ),
    );
  }
}
