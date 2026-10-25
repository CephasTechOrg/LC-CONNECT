import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_skeleton.dart';
import '../../../shared/widgets/app_states.dart';
import '../providers/student_directory_provider.dart';
import '../../../core/theme/app_spacing.dart';

/// The Connect tab as a staff member sees it: a searchable directory of students they can open
/// and message. Replaces the old dead-end that pointed staff at the (staff-only) directory.
class StaffStudentDirectory extends ConsumerStatefulWidget {
  const StaffStudentDirectory({super.key});

  @override
  ConsumerState<StaffStudentDirectory> createState() => _StaffStudentDirectoryState();
}

class _StaffStudentDirectoryState extends ConsumerState<StaffStudentDirectory> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentDirectoryProvider(_query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppShellHeader(
          title: 'Students',
          subtitle: 'Find and message any student at Livingstone',
        ),
        // The shared search field, so it matches Messages and New message.
        AppSearchField(
          controller: _searchCtrl,
          hasText: _query.isNotEmpty,
          hint: 'Search by name or major',
          onChanged: (v) => setState(() => _query = v.trim()),
          onClear: () {
            _searchCtrl.clear();
            setState(() => _query = '');
          },
        ),
        Expanded(
          child: studentsAsync.when(
            loading: () => const AppListSkeleton(count: 3),
            error: (_, _) => AppErrorState(
              message: 'Could not load students.',
              onRetry: () => ref.invalidate(studentDirectoryProvider(_query)),
            ),
            data: (students) {
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => ref.refresh(studentDirectoryProvider(_query).future),
                child: students.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.12),
                          AppEmptyState(
                            icon: Icons.school_outlined,
                            title: _query.isEmpty ? 'No students yet' : 'No students found',
                            subtitle: _query.isEmpty
                                ? 'Students will appear here as they join.'
                                : 'Try a different name or major.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.gutter,
                          AppSpacing.xs,
                          AppSpacing.gutter,
                          AppSpacing.xxl,
                        ),
                        itemCount: students.length,
                        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                        itemBuilder: (_, i) => _StudentTile(
                          student: students[i],
                          onTap: () => context.push(
                            '/users/${students[i].profileId}',
                            extra: students[i].displayName,
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StudentTile extends StatelessWidget {
  final StudentEntry student;
  final VoidCallback onTap;
  const _StudentTile({required this.student, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (student.major != null && student.major!.isNotEmpty) student.major!,
      if (student.classYear != null) 'Class of ${student.classYear}',
    ].join(' · ');

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          AvatarWidget(imageUrl: student.avatarUrl, size: 44, cacheScope: student.userId),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
