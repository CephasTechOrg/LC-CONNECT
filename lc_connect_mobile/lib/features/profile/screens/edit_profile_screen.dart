import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../providers/profile_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _pronounsCtrl = TextEditingController();
  final _majorCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _campusCtrl = TextEditingController();
  int? _classYear;
  final Set<String> _interests = {};
  final Set<String> _langSpoken = {};
  final Set<String> _langLearning = {};
  final Set<String> _lookingFor = {};
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pronounsCtrl.dispose();
    _majorCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _campusCtrl.dispose();
    super.dispose();
  }

  void _initFrom(MyProfile p) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = p.displayName ?? '';
    _pronounsCtrl.text = p.pronouns ?? '';
    _majorCtrl.text = p.major ?? '';
    _bioCtrl.text = p.bio ?? '';
    _locationCtrl.text = p.countryState ?? '';
    _campusCtrl.text = p.campus ?? '';
    _classYear = p.classYear;
    _interests
      ..clear()
      ..addAll(p.interests);
    _langSpoken
      ..clear()
      ..addAll(p.languagesSpoken);
    _langLearning
      ..clear()
      ..addAll(p.languagesLearning);
    _lookingFor
      ..clear()
      ..addAll(p.lookingForCodes);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final major = _majorCtrl.text.trim();
    if (name.isEmpty || major.isEmpty || _lookingFor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Name, major, and at least one "Looking For" are required.',
              style: GoogleFonts.dmSans()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(myProfileNotifierProvider.notifier).updateProfile(
            displayName: name,
            pronouns: _pronounsCtrl.text.trim(),
            major: major,
            classYear: _classYear,
            countryState: _locationCtrl.text.trim(),
            campus: _campusCtrl.text.trim(),
            bio: _bioCtrl.text.trim(),
            interests: _interests.toList(),
            languagesSpoken: _langSpoken.toList(),
            languagesLearning: _langLearning.toList(),
            lookingForCodes: _lookingFor.toList(),
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save. Please try again.',
                style: GoogleFonts.dmSans()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileNotifierProvider);
    final lookupsAsync = ref.watch(lookupDataProvider);

    return profileAsync.when(
      loading: () => Scaffold(
        appBar: _appBar(null),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Scaffold(
        appBar: _appBar(null),
        body: Center(
          child: TextButton(
            onPressed: () => ref.invalidate(myProfileNotifierProvider),
            child: const Text('Retry'),
          ),
        ),
      ),
      data: (profile) {
        _initFrom(profile);
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _appBar(_save),
          body: lookupsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: TextButton(
                onPressed: () => ref.invalidate(lookupDataProvider),
                child: const Text('Retry'),
              ),
            ),
            data: (lookups) => _buildForm(lookups),
          ),
        );
      },
    );
  }

  AppBar _appBar(VoidCallback? onSave) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textDark),
        onPressed: () => context.pop(),
      ),
      title: Text(
        'Edit Profile',
        style: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      ),
      actions: [
        if (_saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else
          TextButton(
            onPressed: onSave,
            child: Text(
              'Save',
              style: GoogleFonts.dmSans(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildForm(LookupData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section('Basics'),
          const SizedBox(height: 16),
          _textField(
            controller: _nameCtrl,
            label: 'Full Name',
            hint: 'Your display name',
            icon: Icons.person_outline_rounded,
            capitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          _textField(
            controller: _pronounsCtrl,
            label: 'Pronouns',
            hint: 'e.g., she/her, he/him, they/them',
            icon: Icons.tag_rounded,
            optional: true,
          ),
          const SizedBox(height: 14),
          _textField(
            controller: _majorCtrl,
            label: 'Major',
            hint: 'e.g., Business Administration',
            icon: Icons.school_outlined,
            capitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 14),
          _FieldLabel('Class Year', optional: true),
          DropdownButtonFormField<int>(
            initialValue: _classYear,
            onChanged: (v) => setState(() => _classYear = v),
            style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textDark),
            decoration: const InputDecoration(
              hintText: 'Select graduation year',
              prefixIcon: Icon(Icons.calendar_today_outlined,
                  size: 18, color: AppColors.textMuted),
            ),
            items: List.generate(10, (i) => 2022 + i)
                .map((y) =>
                    DropdownMenuItem(value: y, child: Text('$y')))
                .toList(),
          ),
          const SizedBox(height: 28),
          _section('Location'),
          const SizedBox(height: 16),
          _textField(
            controller: _locationCtrl,
            label: 'Where are you from?',
            hint: 'e.g., Atlanta, GA',
            icon: Icons.location_on_outlined,
            optional: true,
          ),
          const SizedBox(height: 14),
          _textField(
            controller: _campusCtrl,
            label: 'Campus',
            hint: 'e.g., Main Campus',
            icon: Icons.apartment_outlined,
            optional: true,
          ),
          const SizedBox(height: 28),
          _section('About'),
          const SizedBox(height: 16),
          _FieldLabel('Short Bio', optional: true),
          TextFormField(
            controller: _bioCtrl,
            maxLines: 4,
            maxLength: 500,
            style: GoogleFonts.dmSans(
                fontSize: 14, color: AppColors.textDark),
            decoration: const InputDecoration(
              hintText: 'Tell people about yourself...',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 28),
          _section('Interests', optional: true),
          const SizedBox(height: 12),
          _ChipGrid(
            options: data.interests,
            selected: _interests,
            onToggle: (v) => setState(() {
              _interests.contains(v)
                  ? _interests.remove(v)
                  : _interests.add(v);
            }),
          ),
          const SizedBox(height: 28),
          _section('Languages I speak', optional: true),
          const SizedBox(height: 12),
          _ChipGrid(
            options: data.languages,
            selected: _langSpoken,
            onToggle: (v) => setState(() {
              _langSpoken.contains(v)
                  ? _langSpoken.remove(v)
                  : _langSpoken.add(v);
            }),
          ),
          const SizedBox(height: 28),
          _section("Languages I'm learning", optional: true),
          const SizedBox(height: 12),
          _ChipGrid(
            options: data.languages,
            selected: _langLearning,
            onToggle: (v) => setState(() {
              _langLearning.contains(v)
                  ? _langLearning.remove(v)
                  : _langLearning.add(v);
            }),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                'Looking For',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '— pick at least one',
                style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ChipGrid(
            options: data.lookingFor.map((l) => l['name']!).toList(),
            optionKeys: data.lookingFor.map((l) => l['code']!).toList(),
            selected: _lookingFor,
            onToggle: (v) => setState(() {
              _lookingFor.contains(v)
                  ? _lookingFor.remove(v)
                  : _lookingFor.add(v);
            }),
            highlight: true,
          ),
          const SizedBox(height: 36),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Save Changes',
                      style: GoogleFonts.dmSans(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, {bool optional = false}) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 8),
          Text(
            'optional',
            style: GoogleFonts.dmSans(
                fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool optional = false,
    TextCapitalization capitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label, optional: optional),
        TextFormField(
          controller: controller,
          onChanged: onChanged,
          textCapitalization: capitalization,
          style: GoogleFonts.dmSans(
              fontSize: 14, color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon:
                Icon(icon, size: 18, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool optional;
  const _FieldLabel(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            text,
            style: GoogleFonts.dmSans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMid,
            ),
          ),
          if (optional) ...[
            const SizedBox(width: 6),
            Text(
              'optional',
              style: GoogleFonts.dmSans(
                  fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipGrid extends StatelessWidget {
  final List<String> options;
  final List<String>? optionKeys;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool highlight;

  const _ChipGrid({
    required this.options,
    this.optionKeys,
    required this.selected,
    required this.onToggle,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(options.length, (i) {
        final key = optionKeys?[i] ?? options[i];
        final label = options[i];
        final isOn = selected.contains(key);
        return GestureDetector(
          onTap: () => onToggle(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isOn
                  ? (highlight ? AppColors.primary : AppColors.primarySoft)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOn ? AppColors.primary : AppColors.border,
                width: 1.5,
              ),
            ),
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: isOn ? FontWeight.w600 : FontWeight.w400,
                color: isOn
                    ? (highlight ? Colors.white : AppColors.primary)
                    : AppColors.textMid,
              ),
            ),
          ),
        );
      }),
    );
  }
}
