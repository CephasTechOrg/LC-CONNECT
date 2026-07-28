import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_widget.dart';
import '../../../shared/widgets/app_shell_header.dart';
import '../../../shared/widgets/app_states.dart';
import '../providers/student_directory_provider.dart';

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
          showBottomBorder: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search by name or major',
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
        Expanded(
          child: studentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => AppErrorState(
              message: 'Could not load students.',
              onRetry: () => ref.invalidate(studentDirectoryProvider(_query)),
            ),
            data: (students) {
              if (students.isEmpty) {
                return AppEmptyState(
                  icon: Icons.school_outlined,
                  title: _query.isEmpty ? 'No students yet' : 'No students found',
                  subtitle: _query.isEmpty
                      ? 'Students will appear here as they join.'
                      : 'Try a different name or major.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                itemCount: students.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _StudentTile(
                  student: students[i],
                  onTap: () => context.push(
                    '/users/${students[i].profileId}',
                    extra: students[i].displayName,
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

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              AvatarWidget(imageUrl: student.avatarUrl, size: 44, cacheScope: student.userId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
                      ),
                    ],
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
