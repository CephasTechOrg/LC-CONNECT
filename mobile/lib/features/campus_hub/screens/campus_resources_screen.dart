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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => context.pop(),
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
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: resourceCategories.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppFilterChip(
                      label: entry.value,
                      selected: _category == entry.key,
                      onTap: () => setState(() => _category = entry.key),
                    ),
                  );
                }).toList(),
              ),
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
                      return const AppEmptyState(
                        icon: Icons.menu_book_outlined,
                        title: 'No resources found',
                        subtitle: 'Try another category or check back later.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: resources.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final resource = resources[index];
                        return _ResourceCard(
                          resource: resource,
                          onOpenLink: resource.externalUrl != null
                              ? () => _launch(resource.externalUrl!)
                              : null,
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
