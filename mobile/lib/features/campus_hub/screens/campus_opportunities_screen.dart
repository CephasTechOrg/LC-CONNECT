import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_states.dart';
import '../../programs/providers/programs_provider.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../providers/opportunity_badge_provider.dart';
import '../widgets/campus_subpage_header.dart';
import '../widgets/opportunity_card.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/util/caching.dart';

const _categoryFilters = <String, String>{
  'all': 'All types',
  'internship': 'Internships',
  'job': 'Jobs',
  'volunteer': 'Volunteering',
  'leadership': 'Leadership',
};

/// Spec: All / Campus / Blueprint Bond. Blueprint Bond is scholar-only.
enum _SourceTab { all, campus, blueprintBond }

class CampusOpportunitiesScreen extends ConsumerStatefulWidget {
  const CampusOpportunitiesScreen({super.key});

  @override
  ConsumerState<CampusOpportunitiesScreen> createState() => _OpportunitiesState();
}

class _OpportunitiesState extends ConsumerState<CampusOpportunitiesScreen> {
  String _category = 'all';
  _SourceTab _source = _SourceTab.all;

  @override
  void initState() {
    super.initState();
    // Opening the list clears the hub Opportunities badge (separate from announcement unread).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(opportunityNewCountProvider.notifier).markSeen();
    });
  }

  static const _pageSize = 30;
  int _pages = 1;

  CampusPostsQuery _query([int page = 0]) => CampusPostsQuery(
        kind: 'opportunity',
        category: _category == 'all' ? null : _category,
        pageSize: _pageSize,
        page: page,
      );

  /// Every loaded page in order, whether more may follow, and whether one is still loading.
  ({List<CampusPostSummary> posts, bool hasMore, bool loadingMore}) _loaded(List<CampusPostSummary> first) {
    final posts = [...first];
    var last = first;
    for (var page = 1; page < _pages; page++) {
      final rows = ref.watch(campusPostsProvider(_query(page))).value;
      if (rows == null) return (posts: posts, hasMore: false, loadingMore: true);
      posts.addAll(rows);
      last = rows;
    }
    return (posts: posts, hasMore: last.length >= _pageSize, loadingMore: false);
  }

  List<CampusPostSummary> _bySource(List<CampusPostSummary> posts, _SourceTab source) {
    switch (source) {
      case _SourceTab.all:
        return posts;
      case _SourceTab.campus:
        return posts.where((p) => !p.isBlueprintBond).toList();
      case _SourceTab.blueprintBond:
        return posts.where((p) => p.isBlueprintBond).toList();
    }
  }

  String _emptyTitle(_SourceTab source) {
    switch (source) {
      case _SourceTab.blueprintBond:
        return 'No Blueprint Bond opportunities';
      case _SourceTab.campus:
        return 'No campus opportunities';
      case _SourceTab.all:
        return 'No opportunities yet';
    }
  }

  String _emptySubtitle(_SourceTab source) {
    switch (source) {
      case _SourceTab.blueprintBond:
        return 'Approved employer partner roles for Presidential Scholars will appear here.';
      case _SourceTab.campus:
        return 'Campus jobs, internships, and leadership roles will appear here.';
      case _SourceTab.all:
        return 'Jobs, internships, and campus roles will appear here when published.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(campusPostsProvider(_query()));
    final isVerifiedScholar = ref.watch(scholarEligibilityProvider).isPermitted;
    // Non-scholars never receive Blueprint Bond posts; keep filtering campus-facing.
    final source = isVerifiedScholar ? _source : _SourceTab.all;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CampusSubpageHeader(
              title: 'Opportunities',
              subtitle: isVerifiedScholar
                  ? 'Campus roles and Blueprint Bond openings'
                  : 'Jobs, internships, and campus roles',
              onBack: () => context.pop(),
            ),
            if (isVerifiedScholar) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: _SourceSwitch(
                  selected: source,
                  onChanged: (tab) => setState(() => _source = tab),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Full 48dp chips: this row was boxed to 36dp, squeezing every chip's tap target.
            AppFilterChipRow(
              labels: _categoryFilters.values.toList(),
              selected: _categoryFilters[_category] ?? 'All',
              onSelect: (label) => setState(() {
                _category = _categoryFilters.entries.firstWhere((e) => e.value == label).key;
                _pages = 1;
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async {
                  ref.invalidate(campusPostsProvider);
                  setState(() => _pages = 1);
                  await ref.read(campusPostsProvider(_query()).future);
                },
                child: postsAsync.cached(
                  // A skeleton in the shape of the content that is coming, not a spinner: the Campus Hub
                  // sub-pages were the only lists in the app that spun while every other list
                  // showed placeholders (4.2).
                  loading: () => const AppHubPanelSkeleton(count: 4),
                  error: (_, _) => AppErrorState(
                    message: 'Could not load opportunities.',
                    onRetry: () => ref.invalidate(campusPostsProvider(_query())),
                  ),
                  data: (firstPage) {
                    final loaded = _loaded(firstPage);
                    final posts = _bySource(loaded.posts, source);
                    if (posts.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.work_outline,
                        title: _emptyTitle(source),
                        subtitle: _emptySubtitle(source),
                      );
                    }
                    final footer = loaded.loadingMore || loaded.hasMore;
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: posts.length + (footer ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == posts.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: loaded.loadingMore
                                ? const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : TextButton(
                                    onPressed: () => setState(() => _pages++),
                                    child: const Text('Show more opportunities'),
                                  ),
                          );
                        }
                        return Padding(
                          padding: EdgeInsets.only(bottom: index < posts.length - 1 ? 14 : 0),
                          child: OpportunityCard(
                            post: posts[index],
                            onTap: () => context.push('/home/posts/${posts[index].id}'),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary Campus ↔ Blueprint Bond switch (plus All). Visually distinct from category chips.
class _SourceSwitch extends StatelessWidget {
  final _SourceTab selected;
  final ValueChanged<_SourceTab> onChanged;

  const _SourceSwitch({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EFF6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _Seg(
            label: 'All',
            selected: selected == _SourceTab.all,
            onTap: () => onChanged(_SourceTab.all),
          ),
          _Seg(
            label: 'Campus',
            selected: selected == _SourceTab.campus,
            onTap: () => onChanged(_SourceTab.campus),
          ),
          _Seg(
            label: 'Blueprint Bond',
            selected: selected == _SourceTab.blueprintBond,
            onTap: () => onChanged(_SourceTab.blueprintBond),
          ),
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Seg({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        elevation: selected ? 1 : 0,
        shadowColor: const Color(0x1A312B3C),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.textDark : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
