import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_states.dart';
import '../providers/campus_directory_provider.dart';

class CampusDirectoryScreen extends ConsumerStatefulWidget {
  const CampusDirectoryScreen({super.key});

  @override
  ConsumerState<CampusDirectoryScreen> createState() => _CampusDirectoryScreenState();
}

class _CampusDirectoryScreenState extends ConsumerState<CampusDirectoryScreen> {
  final _searchCtrl = TextEditingController();
  String _category = 'all';
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DirectoryQuery get _directoryQuery => DirectoryQuery(
        category: _category == 'all' ? null : _category,
        query: _query.isEmpty ? null : _query,
      );

  @override
  Widget build(BuildContext context) {
    final directoryAsync = ref.watch(campusDirectoryProvider(_directoryQuery));

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
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/home'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Campus Directory',
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                        Text(
                          'Verified staff contacts at Livingstone',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by name, title, or department',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: directoryCategories.entries.map((entry) {
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
              child: directoryAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => AppErrorState(
                  message: 'Could not load the campus directory.',
                  onRetry: () => ref.invalidate(campusDirectoryProvider(_directoryQuery)),
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    return const AppEmptyState(
                      icon: Icons.badge_outlined,
                      title: 'No contacts found',
                      subtitle: 'Try another category or search term.',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _DirectoryTile(
                        entry: entry,
                        onTap: () => context.push('/home/directory/${entry.positionId}'),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  final DirectoryEntry entry;
  final VoidCallback onTap;

  const _DirectoryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              AvatarWidget(
                imageUrl: entry.avatarUrl,
                size: 44,
                cacheScope: entry.userId,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName ?? entry.officialTitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.officialTitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 12.5,
                        color: AppColors.textMid,
                      ),
                    ),
                    Text(
                      entry.department,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
