import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_error.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/providers/auth_provider.dart';
import '../../campus_positions/providers/campus_positions_provider.dart';
import '../data/suggested_name.dart';
import '../widgets/onboarding_header.dart';
import '../widgets/onboarding_shared_widgets.dart';

const _categories = <String, String>{
  'academic': 'Academic',
  'advising': 'Advising',
  'residential_life': 'Residential Life',
  'campus_services': 'Campus Services',
  'campus_safety': 'Campus Safety',
};

class StaffOnboardingScreen extends ConsumerStatefulWidget {
  const StaffOnboardingScreen({super.key});

  @override
  ConsumerState<StaffOnboardingScreen> createState() => _StaffOnboardingScreenState();
}

class _StaffOnboardingScreenState extends ConsumerState<StaffOnboardingScreen> {
  int _step = 0;
  static const _totalSteps = 3;
  bool _loading = false;

  final _nameCtrl = TextEditingController();
  final _pronounsCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();

  String? _category;
  final _titleCtrl = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _officeCtrl = TextEditingController();

  final _phoneCtrl = TextEditingController();
  final _availabilityCtrl = TextEditingController();
  String? _email;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authNotifierProvider).asData?.value;
      _email = user?.email;
      if (_nameCtrl.text.isEmpty && user != null) {
        _nameCtrl.text = suggestedDisplayName(user);
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pronounsCtrl.dispose();
    _bioCtrl.dispose();
    _titleCtrl.dispose();
    _departmentCtrl.dispose();
    _officeCtrl.dispose();
    _phoneCtrl.dispose();
    _availabilityCtrl.dispose();
    super.dispose();
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _nameCtrl.text.trim().isNotEmpty;
      case 1:
        return _category != null &&
            _titleCtrl.text.trim().isNotEmpty &&
            _departmentCtrl.text.trim().isNotEmpty;
      case 2:
        return true;
      default:
        return false;
    }
  }

  void _onNext() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _onBack() {
    if (_step > 0) setState(() => _step--);
  }

  /// True once the profile + position have been stored server-side. From that point a failure
  /// can only be the refresh, which needs different copy and a retry rather than a generic error.
  bool _saved = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    _saved = false;
    try {
      final client = ref.read(apiClientProvider);
      final profileBody = <String, dynamic>{
        'display_name': _nameCtrl.text.trim(),
      };
      if (_pronounsCtrl.text.trim().isNotEmpty) {
        profileBody['pronouns'] = _pronounsCtrl.text.trim();
      }
      if (_bioCtrl.text.trim().isNotEmpty) profileBody['bio'] = _bioCtrl.text.trim();
      await client.dio.patch('/profiles/me', data: profileBody);

      await ref.read(campusPositionsServiceProvider).submitPosition(
            category: _category!,
            officialTitle: _titleCtrl.text.trim(),
            department: _departmentCtrl.text.trim(),
            officeLocation: _officeCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            availability: _availabilityCtrl.text.trim(),
            bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
          );

      _saved = true;
      await ref.read(authNotifierProvider.notifier).refreshProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _saved
                // Everything above succeeded and only the refresh that unlocks the app failed.
                // Saying "something went wrong" here would send the user back to re-enter a form
                // that is already stored.
                ? 'Your details were saved, but we could not finish setting up. '
                    'Check your connection and retry.'
                : apiErrorMessage(e, fallback: 'Something went wrong. Please try again.'),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          action: _saved
              ? SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: _submit,
                )
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const titles = ['Basic profile', 'Campus position', 'Contact and submit'];
    const subtitles = [
      'How you appear on LC Connect',
      'Your official campus role',
      'How students can reach you',
    ];

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            OnboardingHeader(
              flowTitle: onboardingWelcome(
                ref.watch(authNotifierProvider).asData?.value,
                fallback: 'Staff setup',
              ),
              step: _step,
              totalSteps: _totalSteps,
              stepTitle: titles[_step],
              stepSubtitle: subtitles[_step],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter, AppSpacing.xs, AppSpacing.gutter, AppSpacing.xxxl),
                child: _buildStep(),
              ),
            ),
            OnboardingBottomBar(
              step: _step,
              totalSteps: _totalSteps,
              isLoading: _loading,
              canProceed: _canProceed(),
              onBack: _onBack,
              onNext: _onNext,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _stepBasic();
      case 1:
        return _stepPosition();
      default:
        return _stepContact();
    }
  }

  Widget _stepBasic() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const OnboardingLabel('Display name'),
        TextFormField(
          controller: _nameCtrl,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your name on LC Connect'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Pronouns', optional: true),
        TextFormField(
          controller: _pronounsCtrl,
          decoration: const InputDecoration(hintText: 'e.g., she/her, he/him'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Short bio', optional: true),
        TextFormField(
          controller: _bioCtrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'A brief introduction'),
        ),
      ],
    );
  }

  Widget _stepPosition() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const OnboardingLabel('Campus category'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          items: _categories.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) => setState(() => _category = v),
          decoration: const InputDecoration(hintText: 'Select a category'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Official title'),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'e.g., Associate Professor'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Department or office'),
        TextFormField(
          controller: _departmentCtrl,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'e.g., Biology Department'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Office location', optional: true),
        TextFormField(
          controller: _officeCtrl,
          decoration: const InputDecoration(hintText: 'Building and room'),
        ),
      ],
    );
  }

  Widget _stepContact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const OnboardingLabel('Official email'),
        TextFormField(
          initialValue: _email,
          readOnly: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Phone', optional: true),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'Office or campus phone'),
        ),
        const SizedBox(height: 16),
        const OnboardingLabel('Office hours', optional: true),
        TextFormField(
          controller: _availabilityCtrl,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'When students can reach you'),
        ),
        const SizedBox(height: 16),
        Container(
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
                  'Your position will be reviewed by an administrator before appearing in the '
                  'campus directory.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMid, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
