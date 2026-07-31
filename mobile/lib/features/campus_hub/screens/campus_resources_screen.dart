import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_states.dart';
import '../models/campus_resource.dart';
import '../providers/campus_resources_provider.dart';

class _ResourceCategory {
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  const _ResourceCategory({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
}

const _staticCategories = <_ResourceCategory>[
  _ResourceCategory(
    key: 'advising',
    title: 'Academic Advising',
    description: 'Get help with course planning and degree requirements.',
    icon: Icons.account_balance_outlined,
    iconColor: Color(0xFF2563EB),
    iconBg: Color(0xFFE0EDFF),
  ),
  _ResourceCategory(
    key: 'housing',
    title: 'Housing &\nResidence Life',
    description: 'Find housing options and residence life resources.',
    icon: Icons.home_outlined,
    iconColor: Color(0xFFEA580C),
    iconBg: Color(0xFFFFF1E6),
  ),
  _ResourceCategory(
    key: 'financial_aid',
    title: 'Financial Aid',
    description: 'Information on loans, grants, scholarships, and billing.',
    icon: Icons.attach_money_rounded,
    iconColor: Color(0xFF16A34A),
    iconBg: Color(0xFFDCFCE7),
  ),
  _ResourceCategory(
    key: 'health',
    title: 'Health & Wellness',
    description: 'Access health services, counseling, and wellness programs.',
    icon: Icons.favorite_outline_rounded,
    iconColor: Color(0xFF7C3AED),
    iconBg: Color(0xFFF3E8FF),
  ),
  _ResourceCategory(
    key: 'career',
    title: 'Career Services',
    description: 'Resume help, career coaching, and job opportunities.',
    icon: Icons.work_outline_rounded,
    iconColor: Color(0xFFD97706),
    iconBg: Color(0xFFFEF3C7),
  ),
  _ResourceCategory(
    key: 'student_support',
    title: 'Student Support',
    description: 'Support services for personal and academic success.',
    icon: Icons.groups_outlined,
    iconColor: Color(0xFF2563EB),
    iconBg: Color(0xFFE0EDFF),
  ),
];

class CampusResourcesScreen extends ConsumerStatefulWidget {
  const CampusResourcesScreen({super.key});

  @override
  ConsumerState<CampusResourcesScreen> createState() => _CampusResourcesScreenState();
}

class _CampusResourcesScreenState extends ConsumerState<CampusResourcesScreen> {
  String _category = 'all';

  ResourcesQuery get _query => ResourcesQuery(
        category: _category == 'all' ? null : _category,
      );

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
            _FilterBar(
              selected: _category,
              onChanged: (v) => setState(() => _category = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(campusResourcesProvider(_query)),
                child: resourcesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
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
                    return _ResourceList(
                      resources: resources,
                      onOpenLink: _launch,
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
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22, color: AppColors.textMid),
            onPressed: () {},
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
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cat.iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(cat.icon, color: cat.iconColor, size: 24),
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
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: AppColors.textMid,
                    height: 1.4,
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    'View resources',
                    style: GoogleFonts.dmSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ),
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
                color: cat?.iconBg ?? AppColors.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(cat?.icon ?? Icons.info_outline_rounded,
                  color: cat?.iconColor ?? AppColors.primary, size: 30),
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
                color: AppColors.primary,
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
              style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceList extends StatelessWidget {
  final List<CampusResource> resources;
  final Future<void> Function(String url) onOpenLink;

  const _ResourceList({required this.resources, required this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: resources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final resource = resources[index];
        return _ResourceCard(
          resource: resource,
          onOpenLink: resource.externalUrl != null ? () => onOpenLink(resource.externalUrl!) : null,
        );
      },
    );
  }
}

class _ResourceCard extends StatelessWidget {
  final CampusResource resource;
  final VoidCallback? onOpenLink;

  const _ResourceCard({required this.resource, this.onOpenLink});

  @override
  Widget build(BuildContext context) {
    final categoryLabel = resourceCategories[resource.category] ?? resource.category;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            categoryLabel,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            resource.title,
            style: GoogleFonts.dmSans(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            resource.description,
            style: GoogleFonts.dmSans(fontSize: 13, height: 1.4, color: AppColors.textMid),
          ),
          if (resource.location != null && resource.location!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _MetaRow(icon: Icons.location_on_outlined, text: resource.location!),
          ],
          if (resource.hours != null && resource.hours!.isNotEmpty)
            _MetaRow(icon: Icons.schedule_outlined, text: resource.hours!),
          if (resource.contactEmail != null && resource.contactEmail!.isNotEmpty)
            _MetaRow(icon: Icons.email_outlined, text: resource.contactEmail!),
          if (resource.phone != null && resource.phone!.isNotEmpty)
            _MetaRow(icon: Icons.phone_outlined, text: resource.phone!),
          if (onOpenLink != null) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onOpenLink,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Visit website'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
