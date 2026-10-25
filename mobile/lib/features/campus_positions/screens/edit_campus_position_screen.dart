import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_filter_chip.dart';
import '../../../shared/widgets/app_form_section.dart';
import '../../../shared/widgets/app_states.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../providers/campus_positions_provider.dart';

const _categories = <String, String>{
  'academic': 'Academic',
  'advising': 'Advising',
  'residential_life': 'Residential Life',
  'campus_services': 'Campus Services',
  'campus_safety': 'Campus Safety',
};

/// Edit / resubmit campus position after reject or revoke.
class EditCampusPositionScreen extends ConsumerStatefulWidget {
  const EditCampusPositionScreen({super.key});

  @override
  ConsumerState<EditCampusPositionScreen> createState() =>
      _EditCampusPositionScreenState();
}

class _EditCampusPositionScreenState extends ConsumerState<EditCampusPositionScreen> {
  final _titleCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _officeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _availabilityCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  String? _category;
  bool _loading = false;
  bool _hydrated = false;
  String? _status;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _departmentCtrl.dispose();
    _officeCtrl.dispose();
    _phoneCtrl.dispose();
    _availabilityCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _hydrate(CampusPosition position) {
    if (_hydrated) return;
    _hydrated = true;
    _category = position.category;
    _titleCtrl.text = position.officialTitle;
    _departmentCtrl.text = position.department;
    _officeCtrl.text = position.officeLocation ?? '';
    _phoneCtrl.text = position.phone ?? '';
    _availabilityCtrl.text = position.availability ?? '';
    _bioCtrl.text = position.bio ?? '';
    _status = position.status;
  }

  Future<void> _submit() async {
    if (_category == null ||
        _titleCtrl.text.trim().isEmpty ||
        _departmentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category, title, and department are required')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(campusPositionsServiceProvider).submitPosition(
            category: _category!,
            officialTitle: _titleCtrl.text.trim(),
            department: _departmentCtrl.text.trim(),
            officeLocation: _officeCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            availability: _availabilityCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
          );
      ref.invalidate(myProfileNotifierProvider);
      ref.invalidate(myCampusPositionProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Position resubmitted for review')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(e, fallback: 'Could not resubmit position'))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(myCampusPositionProvider);
    final email = ref.watch(authNotifierProvider).asData?.value?.email;
    final position = positionAsync.asData?.value;
    final locked = position?.isVerified ?? true;

    return Scaffold(
      backgroundColor: AppColors.background,
      // An app bar like every other pushed form, rather than a back button that scrolled away
      // with the fields.
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text(locked ? 'Campus position' : 'Update position'),
      ),
      bottomNavigationBar: position == null || locked
          ? null
          : AppFormActionBar(
              child: FilledButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Submitting…' : 'Resubmit for review'),
              ),
            ),
      body: positionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => AppErrorState(
          message: 'Could not load your campus position.',
          onRetry: () => ref.invalidate(myCampusPositionProvider),
        ),
        data: (position) {
          if (position == null) {
            return const AppEmptyState(
              icon: Icons.badge_outlined,
              title: 'No campus position on file',
              subtitle: 'Your position appears here once you have submitted one.',
            );
          }
          _hydrate(position);
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xs,
              AppSpacing.gutter,
              AppSpacing.xxxl,
            ),
            children: [
              _StatusCard(status: _status ?? position.status, email: email),
              AppFormSection(
                step: locked ? null : 1,
                title: 'Your role',
                children: [
                  const _Label('Category'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final entry in _categories.entries)
                        AppFilterChip(
                          label: entry.value,
                          selected: _category == entry.key,
                          onTap: () {
                            if (!locked) setState(() => _category = entry.key);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _field('Official title', _titleCtrl, enabled: !locked),
                  _field('Department', _departmentCtrl, enabled: !locked),
                ],
              ),
              AppFormSection(
                step: locked ? null : 2,
                title: 'How students reach you',
                children: [
                  _field('Office location', _officeCtrl, enabled: !locked),
                  _field('Phone', _phoneCtrl, enabled: !locked),
                  _field('Availability or hours', _availabilityCtrl, enabled: !locked, maxLines: 2),
                  _field('Bio', _bioCtrl, enabled: !locked, maxLines: 3, last: true),
                ],
              ),
              if (locked) ...[
                const SizedBox(height: AppSpacing.lg),
                const _LockedNote(),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    int maxLines = 1,
    bool last = false,
  }) {
    // Label above the field, as on Create activity and Compose post — not a floating label.
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(label),
          TextField(
            controller: controller,
            enabled: enabled,
            maxLines: maxLines,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
      ),
    );
  }
}

/// Where the position stands, as a coloured chip — it used to be the raw value,
/// "Status: pending_review" style, in grey.
class _StatusCard extends StatelessWidget {
  final String status;
  final String? email;
  const _StatusCard({required this.status, required this.email});

  @override
  Widget build(BuildContext context) {
    final (String label, Color fg, Color bg, String line) = switch (status) {
      'verified' => ('Verified', AppColors.green, AppColors.greenSoft,
          'Shown in the campus directory.'),
      'pending' => ('Pending review', AppColors.warning, AppColors.warningSoft,
          'An administrator will review it before it appears in the directory.'),
      'rejected' => ('Not approved', AppColors.errorText, AppColors.errorSoft,
          'Update the details below and resubmit.'),
      'revoked' => ('Revoked', AppColors.errorText, AppColors.errorSoft,
          'Update the details below and resubmit.'),
      _ => (status, AppColors.textMuted, AppColors.quiet, ''),
    };
    final email = this.email;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: bg, borderRadius: AppRadii.all(AppRadii.full)),
              child: Text(
                label,
                style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: fg),
              ),
            ),
            if (line.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(line, style: AppTypography.body.copyWith(color: AppColors.textMid)),
            ],
            if (email != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Contact email: $email',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LockedNote extends StatelessWidget {
  const _LockedNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadii.all(AppRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primaryText),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Verified positions cannot be edited here. Contact an administrator to make changes.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMid, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
