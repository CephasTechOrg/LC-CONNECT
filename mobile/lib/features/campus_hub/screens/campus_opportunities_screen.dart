import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_states.dart';
import '../../programs/providers/programs_provider.dart';
import '../models/campus_post.dart';
import '../providers/campus_hub_provider.dart';
import '../widgets/campus_post_style.dart';
import '../widgets/campus_subpage_header.dart';

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

  CampusPostsQuery get _query => CampusPostsQuery(
        kind: 'opportunity',
        category: _category == 'all' ? null : _category,
      );

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
    final postsAsync = ref.watch(campusPostsProvider(_query));
    final isVerifiedScholar = ref.watch(isVerifiedScholarProvider);
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
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: _categoryFilters.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: e.value,
                      selected: _category == e.key,
                      onTap: () => setState(() => _category = e.key),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(campusPostsProvider(_query)),
                child: postsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => AppErrorState(
                    message: 'Could not load opportunities.',
                    onRetry: () => ref.invalidate(campusPostsProvider(_query)),
                  ),
                  data: (allPosts) {
                    final posts = _bySource(allPosts, source);
                    if (posts.isEmpty) {
                      return AppEmptyState(
                        icon: Icons.work_outline,
                        title: _emptyTitle(source),
                        subtitle: _emptySubtitle(source),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: posts.length,
                      itemBuilder: (context, index) => Padding(
                        padding: EdgeInsets.only(bottom: index < posts.length - 1 ? 14 : 0),
                        child: _OpportunityCard(
                          post: posts[index],
                          onTap: () => context.push('/home/posts/${posts[index].id}'),
                        ),
                      ),
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
              style: GoogleFonts.dmSans(
                fontSize: 12.5,
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

class _OpportunityCard extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const _OpportunityCard({required this.post, required this.onTap});

  static String _typeLabel(String category) => opportunityCategoryLabels[category] ??
      (category.isNotEmpty ? '${category[0].toUpperCase()}${category.substring(1)}' : 'Opportunity');

  @override
  Widget build(BuildContext context) {
    final (badgeColor, badgeBg, icon) = campusCategoryStyle('opportunity', post.category);
    final typeLabel = _typeLabel(post.category ?? '');
    final isPartner = post.isEmployerPartner || post.isBlueprintBond;
    final sourceLabel = isPartner ? 'Employer Partner' : 'Campus Opportunity';
    final sourceColor = isPartner ? AppColors.primary : AppColors.textMuted;
    final sourceBg = isPartner ? AppColors.primarySoft : AppColors.background;

    final deadline = post.expiresAt;
    final daysLeft = deadline?.toLocal().difference(DateTime.now()).inDays;
    final closingSoon = daysLeft != null && daysLeft <= 3;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(color: Color(0x0A111827), blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: badgeColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CampusBadge(label: typeLabel, color: badgeColor, background: badgeBg),
                        const SizedBox(width: 6),
                        Flexible(child: CampusBadge(label: sourceLabel, color: sourceColor, background: sourceBg)),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d').format(post.publishAt.toLocal()),
                          style: GoogleFonts.dmSans(fontSize: 11.5, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (post.summary != null && post.summary!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        post.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid, height: 1.35),
                      ),
                    ],
                    if (deadline != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: closingSoon ? const Color(0xFFDC2626) : AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Closes ${DateFormat('MMM d').format(deadline.toLocal())}',
                            style: GoogleFonts.dmSans(
                              fontSize: 11.5,
                              fontWeight: closingSoon ? FontWeight.w700 : FontWeight.w500,
                              color: closingSoon ? const Color(0xFFDC2626) : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
