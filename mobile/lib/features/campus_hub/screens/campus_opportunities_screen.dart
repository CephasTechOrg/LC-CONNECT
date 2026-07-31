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

const _opportunityFilters = <String, String>{
  'all': 'All',
  'internship': 'Internships',
  'job': 'Jobs',
  'volunteer': 'Volunteering',
  'leadership': 'Leadership',
};

// Source tab — independent of the category chips below. The server already never sends a
// Blueprint Bond post to anyone but a verified scholar, so this is a client-side filter over
// posts the user was already allowed to receive, not a second authorization check.
enum _SourceTab { all, campus, blueprintBond }

class CampusOpportunitiesScreen extends ConsumerStatefulWidget {
  const CampusOpportunitiesScreen({super.key});

  @override
  ConsumerState<CampusOpportunitiesScreen> createState() => _OpportunitiesState();
}

class _OpportunitiesState extends ConsumerState<CampusOpportunitiesScreen> {
  String _filter = 'all';
  _SourceTab _sourceTab = _SourceTab.all;

  CampusPostsQuery get _query => CampusPostsQuery(
        kind: 'opportunity',
        category: _filter == 'all' ? null : _filter,
      );

  List<CampusPostSummary> _bySource(List<CampusPostSummary> posts) {
    switch (_sourceTab) {
      case _SourceTab.all:
        return posts;
      case _SourceTab.campus:
        return posts.where((p) => !p.isBlueprintBond).toList();
      case _SourceTab.blueprintBond:
        return posts.where((p) => p.isBlueprintBond).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(campusPostsProvider(_query));
    final isVerifiedScholar = ref.watch(isVerifiedScholarProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Opportunities',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search_rounded, size: 22, color: AppColors.textMid),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: 'All',
                      selected: _sourceTab == _SourceTab.all,
                      onTap: () => setState(() => _sourceTab = _SourceTab.all),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: 'Campus',
                      selected: _sourceTab == _SourceTab.campus,
                      onTap: () => setState(() => _sourceTab = _SourceTab.campus),
                    ),
                  ),
                  if (isVerifiedScholar)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppFilterChip(
                        label: 'Blueprint Bond',
                        selected: _sourceTab == _SourceTab.blueprintBond,
                        onTap: () => setState(() => _sourceTab = _SourceTab.blueprintBond),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: _opportunityFilters.entries.map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: e.value,
                      selected: _filter == e.key,
                      onTap: () => setState(() => _filter = e.key),
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
                    final posts = _bySource(allPosts);
                    if (posts.isEmpty) {
                      return _OpportunitiesEmpty(filter: _filter);
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

class _OpportunityCard extends StatelessWidget {
  final CampusPostSummary post;
  final VoidCallback onTap;

  const _OpportunityCard({required this.post, required this.onTap});

  static const _typeStyles = <String, (Color, Color, IconData)>{
    'internship': (Color(0xFF2563EB), Color(0xFFE0EDFF), Icons.code_rounded),
    'job': (Color(0xFFD97706), Color(0xFFFEF3C7), Icons.work_outline_rounded),
    'volunteer': (Color(0xFF16A34A), Color(0xFFDCFCE7), Icons.favorite_outline_rounded),
    'leadership': (Color(0xFF7C3AED), Color(0xFFF3E8FF), Icons.emoji_events_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final cat = post.category ?? 'internship';
    final (badgeColor, badgeBg, icon) = _typeStyles[cat] ?? _typeStyles['internship']!;
    final typeLabel = _opportunityFilters[cat] ??
        (cat.isNotEmpty ? '${cat[0].toUpperCase()}${cat.substring(1)}' : 'Opportunity');

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
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: badgeColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel.replaceAll(RegExp(r's$'), ''),
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: badgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: post.isEmployerPartner ? const Color(0xFFEFF6FB) : AppColors.background,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            post.isEmployerPartner ? 'Employer Partner' : 'Campus Opportunity',
                            style: GoogleFonts.dmSans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: post.isEmployerPartner ? AppColors.primary : AppColors.textMuted,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('MMM d').format(post.publishAt.toLocal()),
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (post.summary != null && post.summary!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        post.summary!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 13, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          'Salisbury, NC',
                          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          cat == 'internship' ? 'Internship' : 'Part-time',
                          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.bookmark_border_rounded,
                  size: 22,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpportunitiesEmpty extends StatelessWidget {
  final String filter;
  const _OpportunitiesEmpty({required this.filter});

  static const _samples = <(String, String, String, String, String, String)>[
    ('internship', 'Summer Analyst Internship', 'Goldman Sachs', 'New York, NY', 'Full-time', 'Jul 28'),
    ('internship', 'Software Engineering Intern', 'Google', 'Mountain View, CA', 'Internship', 'Jul 27'),
    ('volunteer', 'Community Outreach Volunteer', 'Livingstone Cares', 'Salisbury, NC', 'Part-time', 'Jul 26'),
    ('job', 'Marketing Assistant', 'Livingstone College', 'Salisbury, NC', 'Part-time', 'Jul 25'),
    ('internship', 'Business Development Intern', 'Bank of America', 'Charlotte, NC', 'Internship', 'Jul 24'),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = filter == 'all' ? _samples : _samples.where((s) => s.$1 == filter).toList();

    if (filtered.isEmpty) {
      return const AppEmptyState(
        icon: Icons.work_outline,
        title: 'No opportunities yet',
        subtitle: 'Jobs, internships, and campus roles will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final (cat, title, org, location, schedule, date) = filtered[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index < filtered.length - 1 ? 14 : 0),
          child: _SampleOpportunityCard(
            category: cat,
            title: title,
            org: org,
            location: location,
            schedule: schedule,
            date: date,
          ),
        );
      },
    );
  }
}

class _SampleOpportunityCard extends StatelessWidget {
  final String category;
  final String title;
  final String org;
  final String location;
  final String schedule;
  final String date;

  const _SampleOpportunityCard({
    required this.category,
    required this.title,
    required this.org,
    required this.location,
    required this.schedule,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final (badgeColor, badgeBg, icon) =
        _OpportunityCard._typeStyles[category] ?? _OpportunityCard._typeStyles['internship']!;
    final typeLabel = (_opportunityFilters[category] ?? 'Opportunity').replaceAll(RegExp(r's$'), '');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: badgeColor, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        typeLabel,
                        style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor),
                      ),
                    ),
                    const Spacer(),
                    Text(date, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 15.5, fontWeight: FontWeight.w700, color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                Text(org, style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMid)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(location, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(width: 12),
                    const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(schedule, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.bookmark_border_rounded, size: 22, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
