import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/api/api_error.dart';
import '../../../core/theme/app_theme.dart';
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: positionAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => AppErrorState(
            message: 'Could not load your campus position.',
            onRetry: () => ref.invalidate(myCampusPositionProvider),
          ),
          data: (position) {
            if (position == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No campus position on file.',
                    style: GoogleFonts.dmSans(color: AppColors.textMuted),
                  ),
                ),
              );
            }
            _hydrate(position);
            final locked = position.isVerified;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      onPressed: () => context.pop(),
                    ),
                    Text(
                      locked ? 'Campus position' : 'Update position',
                      style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Status: ${_status!.replaceAll('_', ' ')}',
                    style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted),
                  ),
                ],
                if (email != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Contact email: $email',
                    style: GoogleFonts.dmSans(fontSize: 12.5, color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Category', style: _labelStyle),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _categories.entries.map((entry) {
                    final selected = _category == entry.key;
                    return ChoiceChip(
                      label: Text(entry.value),
                      selected: selected,
                      onSelected: locked
                          ? null
                          : (_) => setState(() => _category = entry.key),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _field('Official title', _titleCtrl, enabled: !locked),
                _field('Department', _departmentCtrl, enabled: !locked),
                _field('Office location', _officeCtrl, enabled: !locked),
                _field('Phone', _phoneCtrl, enabled: !locked),
                _field('Availability / hours', _availabilityCtrl, enabled: !locked, maxLines: 2),
                _field('Bio', _bioCtrl, enabled: !locked, maxLines: 3),
                const SizedBox(height: 20),
                if (!locked)
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Text(_loading ? 'Submitting…' : 'Resubmit for review'),
                  )
                else
                  Text(
                    'Verified positions cannot be edited here. Contact an administrator to make changes.',
                    style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textMuted, height: 1.4),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  TextStyle get _labelStyle => GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        enabled: enabled,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
