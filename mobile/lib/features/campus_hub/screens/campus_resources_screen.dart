import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_states.dart';
import '../models/campus_resource.dart';
import '../providers/campus_resources_provider.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_skeleton.dart';

part '../widgets/campus_resource_card.dart';

class _ResourceCategory {
  final String key;
  final String title;
  final String description;
  final IconData icon;

  const _ResourceCategory({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
  });
}

/// Every category shares the app's one tint (see campus_post_style.dart). The grid used to give
/// each of its six tiles its own colour — blue, orange, green, purple, amber — so the first thing
/// on the page was six colours competing. They are told apart by icon and title instead.
const _staticCategories = <_ResourceCategory>[
  _ResourceCategory(
    key: 'advising',
    title: 'Academic Advising',
    description: 'Get help with course planning and degree requirements.',
    icon: Icons.account_balance_outlined,
  ),
  _ResourceCategory(
    key: 'housing',
    title: 'Housing &\nResidence Life',
    description: 'Find housing options and residence life resources.',
    icon: Icons.home_outlined,
  ),
  _ResourceCategory(
    key: 'financial_aid',
    title: 'Financial Aid',
    description: 'Information on loans, grants, scholarships, and billing.',
    icon: Icons.attach_money_rounded,
  ),
  _ResourceCategory(
    key: 'health',
    title: 'Health & Wellness',
    description: 'Access health services, counseling, and wellness programs.',
    icon: Icons.favorite_outline_rounded,
  ),
  _ResourceCategory(
    key: 'career',
    title: 'Career Services',
    description: 'Resume help, career coaching, and job opportunities.',
    icon: Icons.work_outline_rounded,
  ),
  _ResourceCategory(
    key: 'student_support',
    title: 'Student Support',
    description: 'Support services for personal and academic success.',
    icon: Icons.groups_outlined,
  ),
];

/// The icon for any resource category, including ones without a grid tile.
IconData _resourceIcon(String category) {
  for (final c in _staticCategories) {
    if (c.key == category) return c.icon;
  }
  return switch (category) {
    'registrar' => Icons.assignment_outlined,
    'safety' => Icons.health_and_safety_outlined,
    'it' => Icons.computer_outlined,
    _ => Icons.info_outline_rounded,
  };
}

class CampusResourcesScreen extends ConsumerStatefulWidget {
  const CampusResourcesScreen({super.key});

  @override
  ConsumerState<CampusResourcesScreen> createState() => _CampusResourcesScreenState();
}

class _CampusResourcesScreenState extends ConsumerState<CampusResourcesScreen> {
  String _category = 'all';

  ResourcesQuery get _query => ResourcesQuery(category: _category == 'all' ? null : _category);

  Future<void> _launch(String url) async {
    if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final resourcesAsync = ref.watch(campusResourcesProvider(_query));

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(onBack: () => context.pop()),
            const SizedBox(height: 8),
            _FilterBar(selected: _category, onChanged: (v) => setState(() => _category = v)),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(campusResourcesProvider(_query)),
                child: resourcesAsync.when(
                  // A skeleton in the shape of the content that is coming, not a spinner: the Campus Hub
                  // sub-pages were the only lists in the app that spun while every other list
                  // showed placeholders (4.2).
                  loading: () => const AppHubPanelSkeleton(count: 4),
                  error: (_, _) => AppErrorState(
                    message: 'Could not load resources.',
                    onRetry: () => ref.invalidate(campusResourcesProvider(_query)),
                  ),
                  data: (resources) {
                    if (resources.isEmpty) {
                      if (_category == 'all') {
                        return _StaticCategoryGrid(
                          onCategoryTap: (key) => setState(() => _category = key),
                        );
                      }
                      return _ComingSoon(
                        category: _category,
                        onBack: () => setState(() => _category = 'all'),
                      );
                    }
                    return _ResourceList(resources: resources, onOpenLink: _launch);
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

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  const _Header({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Campus resources',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  'Services, offices, and support',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _FilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: resourceCategories.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AppFilterChip(
              label: entry.value,
              selected: selected == entry.key,
              onTap: () => onChanged(entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StaticCategoryGrid extends StatelessWidget {
  final ValueChanged<String> onCategoryTap;
  const _StaticCategoryGrid({required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 0.82,
      children: _staticCategories
          .map((cat) => _StaticCategoryCard(cat: cat, onTap: () => onCategoryTap(cat.key)))
          .toList(),
    );
  }
}

class _StaticCategoryCard extends StatelessWidget {
  final _ResourceCategory cat;
  final VoidCallback onTap;

  const _StaticCategoryCard({required this.cat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // The shared card surface (borderless, soft shadow), same as Home and Activities.
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(cat.icon, color: AppColors.primaryText, size: 24),
        ),
        const SizedBox(height: 14),
        Text(
          cat.title,
          style: GoogleFonts.dmSans(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Text(
            cat.description,
            style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textMid, height: 1.4),
          ),
        ),
        Row(
          children: [
            Text(
              'View resources',
              style: GoogleFonts.dmSans(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primaryText),
          ],
        ),
        ],
      ),
    );
  }
}

/// Shown when a specific category (tapped from the grid or filter bar) has no resources yet —
/// acknowledges the tap instead of silently re-showing the same grid.
class _ComingSoon extends StatelessWidget {
  final String category;
  final VoidCallback onBack;
  const _ComingSoon({required this.category, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final cat = _staticCategories.where((c) => c.key == category).firstOrNull;
    final label = (cat?.title ?? resourceCategories[category] ?? category).replaceAll('\n', ' ');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                cat?.icon ?? Icons.info_outline_rounded,
                color: AppColors.primaryText,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Coming soon',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "We're still adding ${label.toLowerCase()} resources. Check back soon.",
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to all categories'),
              style: TextButton.styleFrom(foregroundColor: AppColors.primaryText),
            ),
          ],
        ),
      ),
    );
  }
}
